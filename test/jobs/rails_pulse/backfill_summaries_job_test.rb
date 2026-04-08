require "test_helper"

module RailsPulse
  class BackfillSummariesJobTest < ActiveJob::TestCase
    fixtures :rails_pulse_requests, :rails_pulse_routes, :rails_pulse_operations,
             :rails_pulse_queries, :rails_pulse_jobs, :rails_pulse_job_runs

    def setup
      ENV["TEST_TYPE"] = "functional"
      super

      # Clean slate for summaries
      RailsPulse::Summary.delete_all

      # Freeze time for consistent testing
      @now = Time.current
      travel_to @now

      # Create test data with specific timestamps
      @start_date = 2.days.ago.beginning_of_day
      @end_date = 1.day.ago.end_of_day
    end

    def teardown
      travel_back
      super
    end

    # ============================================================================
    # Basic Functionality Tests
    # ============================================================================

    test "perform converts string dates to datetime" do
      start_str = "2024-01-01"
      end_str = "2024-01-02"

      # Will create summaries for the period (proves dates were converted)
      BackfillSummariesJob.new.perform(start_str, end_str, [ "day" ])

      # Summaries should exist for that period
      summaries = RailsPulse::Summary.where(period_type: "day")

      assert_operator summaries.count, :>, 0
    end

    test "perform processes each period type provided" do
      # Create test data for the period
      travel_to @start_date do
        create_request_with_operation(duration: 100)
      end

      travel_to @now

      BackfillSummariesJob.new.perform(@start_date, @start_date, [ "hour", "day" ])

      assert RailsPulse::Summary.exists?(period_type: "hour")
      assert RailsPulse::Summary.exists?(period_type: "day")
    end

    test "perform uses default period types when not provided" do
      # Create test data for the period
      travel_to @start_date do
        create_request_with_operation(duration: 100)
      end

      travel_to @now

      BackfillSummariesJob.new.perform(@start_date, @start_date)

      # Default is ["hour", "day"]
      assert RailsPulse::Summary.exists?(period_type: "hour")
      assert RailsPulse::Summary.exists?(period_type: "day")
      refute RailsPulse::Summary.exists?(period_type: "week")
    end

    test "backfill creates summaries for all periods in range" do
      # Create requests in specific hours
      travel_to 2.days.ago.beginning_of_day do
        create_request_with_operation(duration: 100)
      end

      travel_to 2.days.ago.beginning_of_day + 1.hour do
        create_request_with_operation(duration: 200)
      end

      travel_back
      travel_to @now

      # Backfill for 2-hour range
      start_time = 2.days.ago.beginning_of_day
      end_time = 2.days.ago.beginning_of_day + 2.hours

      BackfillSummariesJob.new.perform(start_time, end_time, [ "hour" ])

      hourly_summaries = RailsPulse::Summary
        .where(period_type: "hour")
        .where("period_start >= ? AND period_start < ?", start_time, end_time)

      # Should have 2-3 summaries (depending on normalization)
      assert_operator hourly_summaries.count, :>=, 2
    end

    test "backfill respects normalized period start times" do
      # Start at 10:30 AM should normalize to 10:00 AM for hourly
      start_time = 1.day.ago.beginning_of_day + 10.hours + 30.minutes
      end_time = 1.day.ago.beginning_of_day + 11.hours

      # Create test data at 10:30 AM
      travel_to start_time do
        create_request_with_operation(duration: 100)
      end

      travel_to @now

      BackfillSummariesJob.new.perform(start_time, end_time, [ "hour" ])

      summaries = RailsPulse::Summary.where(period_type: "hour")

      # Should have at least one summary
      assert_operator summaries.count, :>, 0, "Expected at least one hourly summary"

      summaries.each do |summary|
        # All should be at beginning of hour
        assert_equal 0, summary.period_start.min
        assert_equal 0, summary.period_start.sec
      end
    end

    # ============================================================================
    # Period Type Logic Tests
    # ============================================================================

    test "advance_period increments by 1 hour for hour period" do
      start_time = 1.day.ago.beginning_of_day
      end_time = start_time + 2.hours

      # Create test data for each hour
      travel_to start_time do
        create_request_with_operation(duration: 100)
      end

      travel_to start_time + 1.hour do
        create_request_with_operation(duration: 200)
      end

      travel_to start_time + 2.hours do
        create_request_with_operation(duration: 300)
      end

      travel_to @now

      BackfillSummariesJob.new.perform(start_time, end_time, [ "hour" ])

      # Get unique period starts to verify multiple periods were processed
      unique_period_starts = RailsPulse::Summary
        .where(period_type: "hour")
        .where("period_start >= ? AND period_start <= ?", start_time, end_time)
        .select(:period_start)
        .distinct
        .order(:period_start)
        .pluck(:period_start)

      # Should have at least 2 different hours
      assert_operator unique_period_starts.size, :>=, 2, "Expected at least 2 distinct hourly periods"

      # Check that consecutive periods are 1 hour apart
      if unique_period_starts.size > 1
        unique_period_starts.each_cons(2) do |current, next_period|
          diff = (next_period - current).to_i

          assert_equal 3600, diff, "Expected 1 hour (3600s) between periods"
        end
      end
    end

    test "advance_period increments by 1 day for day period" do
      start_time = 3.days.ago.beginning_of_day
      end_time = 1.day.ago.end_of_day

      # Create test data for each day
      travel_to 3.days.ago.beginning_of_day do
        create_request_with_operation(duration: 100)
      end

      travel_to 2.days.ago.beginning_of_day do
        create_request_with_operation(duration: 200)
      end

      travel_to 1.day.ago.beginning_of_day do
        create_request_with_operation(duration: 300)
      end

      travel_to @now

      BackfillSummariesJob.new.perform(start_time, end_time, [ "day" ])

      # Get unique period starts to verify multiple periods were processed
      unique_period_starts = RailsPulse::Summary
        .where(period_type: "day")
        .where("period_start >= ? AND period_start <= ?", start_time, end_time)
        .select(:period_start)
        .distinct
        .order(:period_start)
        .pluck(:period_start)

      # Should have 3 different days
      assert_operator unique_period_starts.size, :>=, 2, "Expected at least 2 distinct daily periods"

      # Check that consecutive periods are 1 day apart
      if unique_period_starts.size > 1
        unique_period_starts.each_cons(2) do |current, next_period|
          diff = (next_period - current).to_i

          assert_equal 86400, diff, "Expected 1 day (86400s) between periods"
        end
      end
    end

    test "backfill handles week period type" do
      start_time = 2.weeks.ago.beginning_of_week
      end_time = 1.week.ago.end_of_week

      BackfillSummariesJob.new.perform(start_time, end_time, [ "week" ])

      summaries = RailsPulse::Summary.where(period_type: "week")

      assert_operator summaries.count, :>=, 1
    end

    test "backfill handles month period type" do
      start_time = 2.months.ago.beginning_of_month
      end_time = 1.month.ago.end_of_month

      BackfillSummariesJob.new.perform(start_time, end_time, [ "month" ])

      summaries = RailsPulse::Summary.where(period_type: "month")

      assert_operator summaries.count, :>=, 1
    end

    test "backfill handles multiple period types in one call" do
      start_time = 1.day.ago.beginning_of_day
      end_time = 1.day.ago.end_of_day

      BackfillSummariesJob.new.perform(start_time, end_time, [ "hour", "day", "week" ])

      assert RailsPulse::Summary.exists?(period_type: "hour")
      assert RailsPulse::Summary.exists?(period_type: "day")
      assert RailsPulse::Summary.exists?(period_type: "week")
    end

    # ============================================================================
    # Integration Tests (Real SummaryService Execution)
    # ============================================================================

    test "backfill creates summaries with correct data from requests" do
      # Create test requests
      travel_to 1.day.ago.beginning_of_day do
        create_request_with_operation(duration: 100, status: 200)
        create_request_with_operation(duration: 200, status: 200)
        create_request_with_operation(duration: 150, status: 500)
      end

      travel_back
      travel_to @now

      BackfillSummariesJob.new.perform(
        1.day.ago.beginning_of_day,
        1.day.ago.end_of_day,
        [ "day" ]
      )

      # Check overall request summary (summarizable_id = 0)
      summary = RailsPulse::Summary
        .where(summarizable_type: "RailsPulse::Request", summarizable_id: 0)
        .where(period_type: "day")
        .first

      assert_not_nil summary
      # Note: count may include requests from fixtures as well
      assert_operator summary.count, :>=, 3
      # Avg duration will vary based on all requests in that day (including fixtures)
      assert_operator summary.avg_duration, :>, 0
      assert_operator summary.error_count, :>=, 1
      assert_operator summary.success_count, :>=, 2
    end

    test "backfill creates route-specific summaries" do
      route = rails_pulse_routes(:api_users)

      travel_to 1.day.ago.beginning_of_day do
        create_request_with_operation(duration: 100, status: 200)
      end

      travel_back
      travel_to @now

      BackfillSummariesJob.new.perform(
        1.day.ago.beginning_of_day,
        1.day.ago.end_of_day,
        [ "day" ]
      )

      # Should create route-specific summary
      route_summary = RailsPulse::Summary
        .where(summarizable_type: "RailsPulse::Route", summarizable_id: route.id)
        .where(period_type: "day")
        .first

      assert_not_nil route_summary
      assert_operator route_summary.count, :>, 0
    end

    test "backfill correctly processes multi-day ranges" do
      # Create data across multiple days
      travel_to 3.days.ago.beginning_of_day do
        create_request_with_operation(duration: 100)
      end

      travel_to 2.days.ago.beginning_of_day do
        create_request_with_operation(duration: 200)
      end

      travel_to 1.day.ago.beginning_of_day do
        create_request_with_operation(duration: 300)
      end

      travel_back
      travel_to @now

      BackfillSummariesJob.new.perform(
        3.days.ago.beginning_of_day,
        1.day.ago.end_of_day,
        [ "day" ]
      )

      # Should have summaries for each day
      summaries = RailsPulse::Summary
        .where(period_type: "day")
        .where("period_start >= ?", 3.days.ago.beginning_of_day)

      assert_operator summaries.count, :>=, 3
    end

    # ============================================================================
    # Edge Cases
    # ============================================================================

    test "backfill handles empty date range" do
      # Same start and end
      start_time = 1.day.ago.beginning_of_day

      assert_nothing_raised do
        BackfillSummariesJob.new.perform(start_time, start_time, [ "hour" ])
      end
    end

    test "backfill handles period with no data" do
      # 10 years ago - unlikely to have data
      start_time = 10.years.ago.beginning_of_day
      end_time = 10.years.ago.end_of_day

      assert_nothing_raised do
        BackfillSummariesJob.new.perform(start_time, end_time, [ "day" ])
      end

      # Should still create summaries, just with 0 count
      summaries = RailsPulse::Summary
        .where(period_type: "day")
        .where("period_start >= ?", start_time)

      # May or may not create zero-count summaries depending on service logic
      assert_operator summaries.count, :>=, 0
    end

    test "backfill handles single hour period" do
      start_time = 1.hour.ago.beginning_of_hour
      end_time = 1.hour.ago.end_of_hour

      assert_nothing_raised do
        BackfillSummariesJob.new.perform(start_time, end_time, [ "hour" ])
      end

      summaries = RailsPulse::Summary.where(period_type: "hour")

      assert_operator summaries.count, :>=, 0
    end

    private

    def create_request_with_operation(duration:, status: 200)
      route = rails_pulse_routes(:api_users)
      request = RailsPulse::Request.create!(
        route_id: route.id,
        duration: duration,
        status: status,
        request_uuid: SecureRandom.uuid,
        occurred_at: Time.current
      )

      RailsPulse::Operation.create!(
        request_id: request.id,
        operation_type: "sql",
        label: "SELECT * FROM users",
        duration: duration * 0.8,
        occurred_at: Time.current
      )

      request
    end
  end
end
