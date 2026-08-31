require "test_helper"

module RailsPulse
  module Operations
    class CompareTest < ActiveSupport::TestCase
      fixtures :rails_pulse_routes

      def setup
        @route = rails_pulse_routes(:api_users)
        @now   = Time.utc(2026, 6, 15, 12, 0, 0)
        travel_to @now
        RailsPulse::Summary.delete_all
      end

      def teardown
        travel_back
      end

      # Builds a day summary for the route, `days_ago` before the frozen now.
      def summary_for(days_ago, p95:, count: 500, error_count: 0)
        period_start = (@now - days_ago.days).beginning_of_day

        RailsPulse::Summary.create!(
          summarizable_type: "RailsPulse::Route",
          summarizable_id:   @route.id,
          period_type:       "day",
          period_start:      period_start,
          period_end:        period_start.end_of_day,
          count:             count,
          avg_duration:      p95 * 0.6,
          p50_duration:      p95 * 0.5,
          p95_duration:      p95,
          p99_duration:      p95 * 1.2,
          error_count:       error_count,
          success_count:     count - error_count
        )
      end

      def steady_history(p95: 200.0, days: 10)
        (1..days).each { |ago| summary_for(ago, p95: p95) }
      end

      # Structure Tests

      test "returns a Comparison carrying both sides of the measurement" do
        steady_history
        summary_for(0, p95: 900.0)

        comparison = Compare.call(@route)

        assert_instance_of Comparison, comparison
        assert_equal :p95, comparison.metric
        assert_equal "day", comparison.period_type
        assert_in_delta 200.0, comparison.baseline_value, 0.01
        assert_in_delta 900.0, comparison.current_value, 0.01
      end

      test "accepts :requests for the overall application rollup" do
        period_start = @now.beginning_of_day
        RailsPulse::Summary.create!(
          summarizable_type: "RailsPulse::Request",
          summarizable_id:   0,
          period_type:       "day",
          period_start:      period_start,
          period_end:        period_start.end_of_day,
          count:             100,
          p95_duration:      300.0
        )

        comparison = Compare.call(:requests)

        assert_equal "RailsPulse::Request", comparison.subject.type
        assert_in_delta 300.0, comparison.current_value, 0.01
      end

      test "rejects a subject summaries are not kept for" do
        assert_raises(ArgumentError) { Compare.call(Object.new) }
      end

      test "rejects an unsupported metric" do
        assert_raises(ArgumentError) { Compare.call(@route, metric: :median) }
      end

      # Calculation Tests

      test "baseline is traffic weighted, not a flat average of periods" do
        # One busy slow day and many quiet fast ones: an unweighted mean would
        # sit near the quiet days, a weighted one near the busy day.
        summary_for(1, p95: 1000.0, count: 10_000)
        (2..6).each { |ago| summary_for(ago, p95: 100.0, count: 100) }
        summary_for(0, p95: 100.0)

        comparison = Compare.call(@route)

        assert_operator comparison.baseline_value, :>, 900.0
      end

      test "baseline excludes the current window" do
        steady_history(p95: 200.0)
        summary_for(0, p95: 5000.0)

        comparison = Compare.call(@route)

        # The 5000ms day must not pull its own baseline up.
        assert_in_delta 200.0, comparison.baseline_value, 0.01
      end

      test "computes delta, ratio and percent change" do
        steady_history(p95: 200.0)
        summary_for(0, p95: 500.0)

        comparison = Compare.call(@route)

        assert_in_delta 300.0, comparison.delta, 0.01
        assert_in_delta 2.5, comparison.ratio, 0.01
        assert_in_delta 150.0, comparison.percent_change, 0.01
        assert_equal :up, comparison.direction
      end

      test "error_rate metric reads from error and success counts" do
        (1..5).each { |ago| summary_for(ago, p95: 200.0, count: 1000, error_count: 10) }
        summary_for(0, p95: 200.0, count: 1000, error_count: 100)

        comparison = Compare.call(@route, metric: :error_rate)

        assert_in_delta 1.0, comparison.baseline_value, 0.01
        assert_in_delta 10.0, comparison.current_value, 0.01
        assert_equal "%", comparison.unit
      end

      # Regression Detection Tests

      test "flags a regression that clears both the ratio and the absolute floor" do
        steady_history(p95: 200.0)
        summary_for(0, p95: 600.0)

        assert_predicate Compare.call(@route), :regression?
      end

      test "does not flag a large ratio below the absolute floor" do
        # 2ms to 4ms doubles, but is not something anyone should be paged about.
        steady_history(p95: 2.0)
        summary_for(0, p95: 4.0)

        comparison = Compare.call(@route)

        assert_operator comparison.ratio, :>=, 2.0
        assert_not_predicate comparison, :regression?
      end

      test "does not flag a large absolute delta below the ratio" do
        steady_history(p95: 4000.0)
        summary_for(0, p95: 4500.0)

        comparison = Compare.call(@route)

        assert_operator comparison.delta, :>, 100.0
        assert_not_predicate comparison, :regression?
      end

      test "does not flag an improvement" do
        steady_history(p95: 900.0)
        summary_for(0, p95: 100.0)

        comparison = Compare.call(@route)

        assert_equal :down, comparison.direction
        assert_not_predicate comparison, :regression?
      end

      # Edge Cases

      test "is not comparable with no history at all" do
        comparison = Compare.call(@route)

        assert_not_predicate comparison, :comparable?
        assert_nil comparison.delta
        assert_not_predicate comparison, :regression?
        assert_equal "not enough data to compare", comparison.summary
      end

      test "is not comparable with a current window but no baseline" do
        summary_for(0, p95: 900.0)

        comparison = Compare.call(@route)

        assert_not_predicate comparison, :comparable?
        assert_not_predicate comparison, :regression?
      end

      test "requires the configured minimum of baseline periods" do
        # Two days of history, below the default minimum of three.
        summary_for(1, p95: 200.0)
        summary_for(2, p95: 200.0)
        summary_for(0, p95: 900.0)

        comparison = Compare.call(@route)

        assert_predicate comparison, :comparable?
        assert_not_predicate comparison, :sufficient_data?
        assert_not_predicate comparison, :regression?
      end

      test "requires the configured minimum sample count" do
        (1..5).each { |ago| summary_for(ago, p95: 200.0, count: 5) }
        summary_for(0, p95: 900.0, count: 5)

        comparison = Compare.call(@route)

        assert_not_predicate comparison, :sufficient_data?
        assert_not_predicate comparison, :regression?
      end

      test "treats a zero baseline as not comparable rather than dividing by it" do
        (1..5).each { |ago| summary_for(ago, p95: 0.0) }
        summary_for(0, p95: 900.0)

        comparison = Compare.call(@route)

        assert_not_predicate comparison, :comparable?
        assert_nil comparison.ratio
      end

      test "to_h exposes the full measurement" do
        steady_history(p95: 200.0)
        summary_for(0, p95: 600.0)

        payload = Compare.call(@route).to_h

        assert_equal "RailsPulse::Route", payload[:subject_type]
        assert_equal @route.id, payload[:subject_id]
        assert_equal :p95, payload[:metric]
        assert payload[:regression]
        assert_in_delta 3.0, payload[:ratio], 0.01
      end

      # Scan Tests

      test "scan returns only subjects with sufficient data" do
        steady_history(p95: 200.0)
        summary_for(0, p95: 600.0)

        comparisons = Compare.scan(RailsPulse::Route.where(id: @route.id))

        assert_equal 1, comparisons.size
        assert_equal @route.id, comparisons.first.subject.id
      end

      test "scan skips subjects without enough history" do
        comparisons = Compare.scan(RailsPulse::Route.where(id: @route.id))

        assert_empty comparisons
      end
    end
  end
end
