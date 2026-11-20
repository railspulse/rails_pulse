require "test_helper"

module RailsPulse
  class BaselineBuilderTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_jobs

    def setup
      RailsPulse::Summary.delete_all

      @route = rails_pulse_routes(:api_users)
      @query = rails_pulse_queries(:simple_query)
      @job = rails_pulse_jobs(:mailer_job)

      @now = Time.zone.parse("2024-03-06 12:30:00")
      travel_to @now
      @today = @now.beginning_of_day
    end

    def teardown
      travel_back
    end

    # Structure Tests

    test "the window is the baseline_window of complete days ending with yesterday" do
      window = BaselineBuilder.new.window

      assert_equal @today - 28.days, window.begin
      assert_equal @today, window.end
      assert_predicate window, :exclude_end?
    end

    test "the baseline columns are available on a current schema" do
      assert_predicate BaselineBuilder, :columns_available?
    end

    test "perform returns the number of subject rows it rewrote" do
      expected = RailsPulse::Route.count + RailsPulse::Query.count + RailsPulse::Job.count

      assert_equal expected, BaselineBuilder.new.perform
    end

    # Calculation Tests

    test "percentiles are the traffic-weighted average of the window's days" do
      day_summary(@route, @today - 1.day, count: 30, p50: 100, p90: 200, p95: 300)
      day_summary(@route, @today - 2.days, count: 10, p50: 500, p90: 600, p95: 700)

      BaselineBuilder.new.perform
      @route.reload

      assert_in_delta 200.0, @route.baseline_p50_duration, 0.001
      assert_in_delta 300.0, @route.baseline_p90_duration, 0.001
      assert_in_delta 400.0, @route.baseline_p95_duration, 0.001
      assert_equal 40, @route.baseline_sample_count
      assert_equal 2, @route.baseline_periods
      assert_equal @now, @route.baseline_computed_at
    end

    test "routes, queries and jobs each get their own baseline" do
      day_summary(@route, @today - 1.day, count: 5, p50: 10, p90: 20, p95: 30)
      day_summary(@query, @today - 1.day, count: 7, p50: 1, p90: 2, p95: 3)
      day_summary(@job, @today - 1.day, count: 9, p50: 1000, p90: 2000, p95: 3000)

      BaselineBuilder.new.perform

      assert_in_delta 20.0, @route.reload.baseline_p90_duration, 0.001
      assert_in_delta 2.0, @query.reload.baseline_p90_duration, 0.001
      assert_in_delta 2000.0, @job.reload.baseline_p90_duration, 0.001
      assert_equal [ 5, 7, 9 ], [ @route, @query, @job ].map(&:baseline_sample_count)
    end

    test "a summary is matched to its subject by type as well as id" do
      query = RailsPulse::Query.create!(id: @route.id + 10_000, hashed_sql: "b" * 32, normalized_sql: "SELECT 1")
      route = RailsPulse::Route.create!(id: query.id, http_methods: [ "GET" ], path: "/same-id", controller_action: "same#id")
      day_summary(query, @today - 1.day, count: 4, p50: 1, p90: 2, p95: 3)

      BaselineBuilder.new.perform

      assert_equal 4, query.reload.baseline_sample_count
      assert_equal 0, route.reload.baseline_sample_count
      assert_nil route.baseline_p90_duration
    end

    # Edge Cases

    test "a subject with no day summaries gets an empty baseline stamped with the rebuild time" do
      BaselineBuilder.new.perform
      @route.reload

      assert_nil @route.baseline_p50_duration
      assert_nil @route.baseline_p90_duration
      assert_nil @route.baseline_p95_duration
      assert_equal 0, @route.baseline_sample_count
      assert_equal 0, @route.baseline_periods
      assert_equal @now, @route.baseline_computed_at
    end

    test "a day with no value for a percentile adds no weight to that percentile" do
      day_summary(@route, @today - 1.day, count: 10, p50: 100, p90: 200, p95: 300)
      day_summary(@route, @today - 2.days, count: 90, p50: 100, p90: nil, p95: 300)

      BaselineBuilder.new.perform
      @route.reload

      assert_in_delta 200.0, @route.baseline_p90_duration, 0.001
      assert_in_delta 100.0, @route.baseline_p50_duration, 0.001
      assert_equal 100, @route.baseline_sample_count
      assert_equal 2, @route.baseline_periods
    end

    test "a percentile no day recorded stays nil while the others are filled" do
      day_summary(@route, @today - 1.day, count: 10, p50: 100, p90: nil, p95: 300)

      BaselineBuilder.new.perform
      @route.reload

      assert_nil @route.baseline_p90_duration
      assert_in_delta 300.0, @route.baseline_p95_duration, 0.001
    end

    test "the window includes its first day and excludes today and anything older" do
      day_summary(@route, @today - 28.days, count: 1, p50: 100, p90: 100, p95: 100)
      day_summary(@route, @today - 29.days, count: 1, p50: 900, p90: 900, p95: 900)
      day_summary(@route, @today, count: 1, p50: 900, p90: 900, p95: 900)

      BaselineBuilder.new.perform
      @route.reload

      assert_in_delta 100.0, @route.baseline_p90_duration, 0.001
      assert_equal 1, @route.baseline_sample_count
      assert_equal 1, @route.baseline_periods
    end

    test "hour, week and month summaries are ignored" do
      %w[hour week month].each do |period_type|
        summary(@route, @today - 7.days, period_type: period_type, count: 50, p50: 900, p90: 900, p95: 900)
      end

      BaselineBuilder.new.perform

      assert_equal 0, @route.reload.baseline_sample_count
      assert_nil @route.baseline_p90_duration
    end

    test "a day with no traffic is not counted as a period" do
      day_summary(@route, @today - 1.day, count: 0, p50: nil, p90: nil, p95: nil)
      day_summary(@route, @today - 2.days, count: 3, p50: 10, p90: 20, p95: 30)

      BaselineBuilder.new.perform

      assert_equal 1, @route.reload.baseline_periods
    end

    test "a baseline is cleared once its history leaves the window" do
      day_summary(@route, @today - 1.day, count: 10, p50: 100, p90: 200, p95: 300)
      BaselineBuilder.new.perform

      later = @now + 40.days
      travel_to later
      BaselineBuilder.new.perform
      @route.reload

      assert_nil @route.baseline_p90_duration
      assert_equal 0, @route.baseline_sample_count
      assert_equal 0, @route.baseline_periods
      assert_equal later, @route.baseline_computed_at
    end

    test "the window follows config.baseline_window" do
      day_summary(@route, @today - 1.day, count: 1, p50: 100, p90: 100, p95: 100)
      day_summary(@route, @today - 10.days, count: 1, p50: 900, p90: 900, p95: 900)

      original = RailsPulse.configuration.baseline_window
      RailsPulse.configuration.baseline_window = 7.days
      BaselineBuilder.new.perform

      assert_in_delta 100.0, @route.reload.baseline_p90_duration, 0.001
    ensure
      RailsPulse.configuration.baseline_window = original
    end

    test "rebuilding leaves updated_at alone" do
      day_summary(@route, @today - 1.day, count: 10, p50: 100, p90: 200, p95: 300)

      assert_no_changes -> { @route.reload.updated_at } do
        BaselineBuilder.new.perform
      end
    end

    test "every row is rewritten when there are more subjects than one batch holds" do
      day_summary(@route, @today - 1.day, count: 10, p50: 100, p90: 200, p95: 300)

      with_batch_size(2) { BaselineBuilder.new.perform }

      assert_equal 0, RailsPulse::Route.where(baseline_computed_at: nil).count
      assert_in_delta 200.0, @route.reload.baseline_p90_duration, 0.001
    end

    private

    def day_summary(subject, day, **values)
      summary(subject, day, period_type: "day", **values)
    end

    def summary(subject, period_start, period_type:, count:, p50:, p90:, p95:)
      RailsPulse::Summary.create!(
        summarizable: subject, period_type: period_type,
        period_start: period_start, period_end: period_start.end_of_day,
        count: count, p50_duration: p50, p90_duration: p90, p95_duration: p95
      )
    end

    def with_batch_size(size)
      original = BaselineBuilder::BATCH_SIZE
      BaselineBuilder.send(:remove_const, :BATCH_SIZE)
      BaselineBuilder.const_set(:BATCH_SIZE, size)
      yield
    ensure
      BaselineBuilder.send(:remove_const, :BATCH_SIZE)
      BaselineBuilder.const_set(:BATCH_SIZE, original)
    end
  end
end
