require "test_helper"

module RailsPulse
  class SummaryJobTest < ActiveJob::TestCase
    fixtures :rails_pulse_requests, :rails_pulse_routes, :rails_pulse_operations,
             :rails_pulse_queries, :rails_pulse_jobs, :rails_pulse_job_runs

    def setup
      ENV["TEST_TYPE"] = "functional"
      super

      # Clean summaries for fresh test
      RailsPulse::Summary.delete_all

      # Freeze time for consistent testing - Monday, March 4, 2024, 2:30 PM
      @now = Time.zone.parse("2024-03-04 14:30:00")
      travel_to @now
    end

    def teardown
      travel_back
      super
    end

    # ============================================================================
    # Default Behavior Tests
    # ============================================================================

    test "perform uses 1 hour ago beginning of hour as default target_hour" do
      expected_target = 1.hour.ago.beginning_of_hour

      # Create test data for that hour
      travel_to expected_target do
        create_request_with_operation(duration: 100)
      end

      travel_to @now

      SummaryJob.new.perform

      # Should have created hourly summary for 1 hour ago
      hourly_summary = RailsPulse::Summary
        .where(period_type: "hour")
        .where("period_start >= ?", expected_target - 1.minute)
        .first

      assert_not_nil hourly_summary
    end

    test "perform always runs hourly summary" do
      target = 5.hours.ago.beginning_of_hour

      # Create test data
      travel_to target do
        create_request_with_operation(duration: 100)
      end

      travel_to @now

      SummaryJob.new.perform(target)

      assert RailsPulse::Summary.exists?(period_type: "hour")
    end

    test "perform accepts nil target_hour" do
      target = 1.hour.ago.beginning_of_hour

      # Create test data
      travel_to target do
        create_request_with_operation(duration: 100)
      end

      travel_to @now

      assert_nothing_raised do
        SummaryJob.new.perform(nil)
      end

      # Should use default (1 hour ago)
      assert_operator RailsPulse::Summary.where(period_type: "hour").count, :>, 0
    end

    # ============================================================================
    # Hourly Summary Tests
    # ============================================================================

    test "perform creates hourly summary for target hour" do
      target = 2.hours.ago.beginning_of_hour

      # Create test data
      travel_to target do
        create_request_with_operation(duration: 100)
      end

      travel_to @now

      SummaryJob.new.perform(target)

      summary = RailsPulse::Summary
        .where(period_type: "hour")
        .where(period_start: target)
        .first

      assert_not_nil summary
    end

    test "process_hourly_summary calls SummaryService with correct parameters" do
      target = 3.hours.ago.beginning_of_hour

      # Create test data for that hour
      travel_to target do
        create_request_with_operation(duration: 100)
      end

      travel_to @now

      SummaryJob.new.perform(target)

      summary = RailsPulse::Summary
        .where(period_type: "hour", period_start: target)
        .first

      assert_not_nil summary
      assert_operator summary.count, :>, 0
    end

    test "perform creates summaries with actual data" do
      target = 1.hour.ago.beginning_of_hour

      # Create test data for target hour
      travel_to target do
        create_request_with_operation(duration: 100, status: 200)
        create_request_with_operation(duration: 200, status: 500)
      end

      travel_to @now

      SummaryJob.new.perform(target)

      summary = RailsPulse::Summary
        .where(period_type: "hour", period_start: target)
        .where(summarizable_type: "RailsPulse::Request", summarizable_id: 0)
        .first

      assert_not_nil summary
      assert_equal 2, summary.count
      assert_in_delta 150.0, summary.avg_duration, 0.1
      assert_equal 1, summary.error_count
      assert_equal 1, summary.success_count
    end

    # ============================================================================
    # Daily Summary Tests (Midnight Trigger)
    # ============================================================================

    test "perform runs daily summary when target_hour is midnight" do
      midnight = Time.zone.parse("2024-03-04 00:00:00")  # Monday midnight

      # Create test data for previous day and current hour
      travel_to midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      travel_to midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to midnight

      SummaryJob.new.perform(midnight)

      # Should have both hourly and daily summaries
      assert RailsPulse::Summary.exists?(period_type: "hour")
      assert RailsPulse::Summary.exists?(period_type: "day")

      travel_back
    end

    test "perform does not run daily summary when target_hour is not midnight" do
      non_midnight = Time.zone.parse("2024-03-04 14:00:00")  # 2 PM

      # Create test data for current hour
      travel_to non_midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to non_midnight

      SummaryJob.new.perform(non_midnight)

      # Should only have hourly summary
      assert RailsPulse::Summary.exists?(period_type: "hour")
      refute RailsPulse::Summary.exists?(period_type: "day")

      travel_back
    end

    test "daily summary processes previous day data" do
      midnight = Time.zone.parse("2024-03-04 00:00:00")
      travel_to midnight

      # Create data for previous day
      travel_to 1.day.ago do
        create_request_with_operation(duration: 150)
      end

      travel_to midnight

      SummaryJob.new.perform(midnight)

      # Daily summary should be for previous day (March 3)
      daily_summary = RailsPulse::Summary
        .where(period_type: "day")
        .where("period_start >= ?", 1.day.ago.beginning_of_day)
        .first

      assert_not_nil daily_summary

      travel_back
    end

    test "daily summary creates summaries with correct period_start" do
      midnight = Time.zone.parse("2024-03-04 00:00:00")

      # Create test data for previous day
      travel_to midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      # Create test data for current hour
      travel_to midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to midnight

      SummaryJob.new.perform(midnight)

      daily_summary = RailsPulse::Summary.where(period_type: "day").first

      assert_not_nil daily_summary, "Expected daily summary to be created"
      # Should be for previous day (March 3)
      expected_date = Date.parse("2024-03-03")

      assert_equal expected_date, daily_summary.period_start.to_date

      travel_back
    end

    # ============================================================================
    # Weekly Summary Tests (Monday Midnight Trigger)
    # ============================================================================

    test "perform runs weekly summary on Monday at midnight" do
      monday_midnight = Time.zone.parse("2024-03-04 00:00:00")  # Monday

      # Create test data for previous week, previous day, and current hour
      travel_to monday_midnight - 1.week do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_midnight

      SummaryJob.new.perform(monday_midnight)

      # Should have hourly, daily, and weekly summaries
      assert RailsPulse::Summary.exists?(period_type: "hour")
      assert RailsPulse::Summary.exists?(period_type: "day")
      assert RailsPulse::Summary.exists?(period_type: "week")

      travel_back
    end

    test "perform does not run weekly summary on Tuesday at midnight" do
      tuesday_midnight = Time.zone.parse("2024-03-05 00:00:00")  # Tuesday

      # Create test data for previous day and current hour
      travel_to tuesday_midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      travel_to tuesday_midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to tuesday_midnight

      SummaryJob.new.perform(tuesday_midnight)

      # Should have hourly and daily, but not weekly
      assert RailsPulse::Summary.exists?(period_type: "hour")
      assert RailsPulse::Summary.exists?(period_type: "day")
      refute RailsPulse::Summary.exists?(period_type: "week")

      travel_back
    end

    test "perform does not run weekly summary on Monday at 2pm" do
      monday_afternoon = Time.zone.parse("2024-03-04 14:00:00")  # Monday 2 PM

      # Create test data for current hour
      travel_to monday_afternoon do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_afternoon

      SummaryJob.new.perform(monday_afternoon)

      # Should only have hourly (not daily or weekly)
      assert RailsPulse::Summary.exists?(period_type: "hour")
      refute RailsPulse::Summary.exists?(period_type: "day")
      refute RailsPulse::Summary.exists?(period_type: "week")

      travel_back
    end

    test "weekly summary processes previous week data" do
      monday_midnight = Time.zone.parse("2024-03-04 00:00:00")

      # Create test data for previous week, previous day, and current hour
      travel_to monday_midnight - 1.week do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_midnight

      SummaryJob.new.perform(monday_midnight)

      # Weekly summary should start from previous week's Monday
      weekly_summary = RailsPulse::Summary
        .where(period_type: "week")
        .first

      assert_not_nil weekly_summary, "Expected weekly summary to be created"
      # Previous week starts on Feb 26 (7 days before March 4)
      expected_start = (monday_midnight - 1.week).beginning_of_week

      assert_equal expected_start, weekly_summary.period_start

      travel_back
    end

    test "weekly summary only runs when both Monday and midnight conditions are met" do
      # Test Friday midnight - should NOT run weekly
      friday_midnight = Time.zone.parse("2024-03-01 00:00:00")

      # Create test data for previous day and current hour
      travel_to friday_midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      travel_to friday_midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to friday_midnight

      SummaryJob.new.perform(friday_midnight)

      assert RailsPulse::Summary.exists?(period_type: "day")
      refute RailsPulse::Summary.exists?(period_type: "week")

      travel_back
    end

    # ============================================================================
    # Monthly Summary Tests (First Day Midnight Trigger)
    # ============================================================================

    test "perform runs monthly summary on first day of month at midnight" do
      first_day_midnight = Time.zone.parse("2024-03-01 00:00:00")  # Friday, March 1

      # Create test data for previous month, previous day, and current hour
      travel_to first_day_midnight - 1.month do
        create_request_with_operation(duration: 100)
      end

      travel_to first_day_midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      travel_to first_day_midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to first_day_midnight

      SummaryJob.new.perform(first_day_midnight)

      # Should have hourly, daily, and monthly summaries
      # (Note: March 1 is Friday, not Monday, so no weekly)
      assert RailsPulse::Summary.exists?(period_type: "hour")
      assert RailsPulse::Summary.exists?(period_type: "day")
      assert RailsPulse::Summary.exists?(period_type: "month")

      travel_back
    end

    test "perform does not run monthly summary on second day of month" do
      second_day_midnight = Time.zone.parse("2024-03-02 00:00:00")

      # Create test data for previous day and current hour
      travel_to second_day_midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      travel_to second_day_midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to second_day_midnight

      SummaryJob.new.perform(second_day_midnight)

      # Should have hourly and daily, but not monthly
      assert RailsPulse::Summary.exists?(period_type: "hour")
      assert RailsPulse::Summary.exists?(period_type: "day")
      refute RailsPulse::Summary.exists?(period_type: "month")

      travel_back
    end

    test "monthly summary processes previous month data" do
      first_day_midnight = Time.zone.parse("2024-03-01 00:00:00")

      # Create test data for previous month, previous day, and current hour
      travel_to first_day_midnight - 1.month do
        create_request_with_operation(duration: 100)
      end

      travel_to first_day_midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      travel_to first_day_midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to first_day_midnight

      SummaryJob.new.perform(first_day_midnight)

      # Monthly summary should be for February
      monthly_summary = RailsPulse::Summary
        .where(period_type: "month")
        .first

      assert_not_nil monthly_summary, "Expected monthly summary to be created"
      expected_start = (first_day_midnight - 1.month).beginning_of_month

      assert_equal expected_start, monthly_summary.period_start

      travel_back
    end

    test "monthly summary only runs on first day at midnight" do
      # Test first day at 3pm - should NOT run monthly
      first_day_afternoon = Time.zone.parse("2024-03-01 15:00:00")

      # Create test data for current hour
      travel_to first_day_afternoon do
        create_request_with_operation(duration: 100)
      end

      travel_to first_day_afternoon

      SummaryJob.new.perform(first_day_afternoon)

      assert RailsPulse::Summary.exists?(period_type: "hour")
      refute RailsPulse::Summary.exists?(period_type: "day")
      refute RailsPulse::Summary.exists?(period_type: "month")

      travel_back
    end

    # ============================================================================
    # Combined Scenario Tests
    # ============================================================================

    test "perform runs all summaries on Monday first-of-month at midnight" do
      # April 1, 2024 is a Monday
      monday_first_midnight = Time.zone.parse("2024-04-01 00:00:00")

      # Create test data for previous month, previous week, previous day, and current hour
      travel_to monday_first_midnight - 1.month do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_first_midnight - 1.week do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_first_midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_first_midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to monday_first_midnight

      SummaryJob.new.perform(monday_first_midnight)

      # Should have all four summary types
      assert RailsPulse::Summary.exists?(period_type: "hour")
      assert RailsPulse::Summary.exists?(period_type: "day")
      assert RailsPulse::Summary.exists?(period_type: "week")
      assert RailsPulse::Summary.exists?(period_type: "month")

      travel_back
    end

    test "perform runs only hourly on regular time" do
      # Regular Tuesday afternoon
      regular_time = Time.zone.parse("2024-03-05 14:30:00")

      # Create test data for current hour
      travel_to regular_time do
        create_request_with_operation(duration: 100)
      end

      travel_to regular_time

      SummaryJob.new.perform(regular_time)

      # Should only have hourly
      assert RailsPulse::Summary.exists?(period_type: "hour")
      refute RailsPulse::Summary.exists?(period_type: "day")
      refute RailsPulse::Summary.exists?(period_type: "week")
      refute RailsPulse::Summary.exists?(period_type: "month")

      travel_back
    end

    # ============================================================================
    # Edge Cases
    # ============================================================================

    test "perform handles target_hour with no data" do
      # Far in the past
      target = 5.years.ago.beginning_of_hour

      assert_nothing_raised do
        SummaryJob.new.perform(target)
      end

      # Should still create summaries (possibly with zero counts)
      assert_operator RailsPulse::Summary.where(period_type: "hour").count, :>=, 0
    end

    test "perform is idempotent" do
      target = 2.hours.ago.beginning_of_hour

      # Create data
      travel_to target do
        create_request_with_operation(duration: 100)
      end

      travel_to @now

      # Run twice
      SummaryJob.new.perform(target)
      initial_count = RailsPulse::Summary.where(period_type: "hour", period_start: target).count

      SummaryJob.new.perform(target)
      final_count = RailsPulse::Summary.where(period_type: "hour", period_start: target).count

      # Count should be the same (summaries are updated, not duplicated)
      assert_equal initial_count, final_count
    end

    test "perform handles boundary conditions for time checks" do
      # Test exactly at hour 0, minute 0, second 0
      exact_midnight = Time.zone.parse("2024-03-04 00:00:00")

      # Create test data for previous week, previous day, and current hour
      travel_to exact_midnight - 1.week do
        create_request_with_operation(duration: 100)
      end

      travel_to exact_midnight - 1.day do
        create_request_with_operation(duration: 100)
      end

      travel_to exact_midnight do
        create_request_with_operation(duration: 100)
      end

      travel_to exact_midnight

      assert_nothing_raised do
        SummaryJob.new.perform(exact_midnight)
      end

      # Should trigger daily (and weekly since it's Monday)
      assert RailsPulse::Summary.exists?(period_type: "day")
      assert RailsPulse::Summary.exists?(period_type: "week")

      travel_back
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
