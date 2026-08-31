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
      def summary_for(days_ago, p95:, count: 500, error_count: 0, subject_id: nil, subject_type: "RailsPulse::Route")
        period_start = (@now - days_ago.days).beginning_of_day

        RailsPulse::Summary.create!(
          summarizable_type: subject_type,
          summarizable_id:   subject_id || @route.id,
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

      # The window under test is the last complete day, so "current" is
      # yesterday and history starts the day before that.
      def current_day(p95:, count: 500, error_count: 0)
        summary_for(1, p95: p95, count: count, error_count: error_count)
      end

      def history(p95: 200.0, days: 10, count: 500, error_count: 0)
        (2..(days + 1)).each { |ago| summary_for(ago, p95: p95, count: count, error_count: error_count) }
      end

      # Structure Tests

      test "returns a Comparison carrying both sides of the measurement" do
        history
        current_day(p95: 900.0)

        comparison = Compare.call(@route)

        assert_instance_of Comparison, comparison
        assert_equal :p95, comparison.metric
        assert_equal "day", comparison.period_type
        assert_in_delta 200.0, comparison.baseline_value, 0.01
        assert_in_delta 900.0, comparison.current_value, 0.01
      end

      test "accepts :requests for the overall application rollup" do
        summary_for(1, p95: 300.0, subject_id: 0, subject_type: "RailsPulse::Request")

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

      # Window Alignment Tests

      test "measures the last complete day, not a rolling 24 hours" do
        # SummaryJob writes a day summary at midnight for the day that just
        # ended, so at noon the newest day summary is yesterday's. An unaligned
        # window would straddle two periods and match neither.
        history
        current_day(p95: 900.0)
        # Today's summary does not exist yet in production; if one did, it must
        # not be mistaken for the completed window.
        summary_for(0, p95: 5.0)

        comparison = Compare.call(@route)

        assert_in_delta 900.0, comparison.current_value, 0.01
      end

      test "baseline excludes the period under test" do
        history(p95: 200.0)
        current_day(p95: 5000.0)

        comparison = Compare.call(@route)

        # The 5000ms day must not pull its own baseline up.
        assert_in_delta 200.0, comparison.baseline_value, 0.01
      end

      # Calculation Tests

      test "baseline is traffic weighted, not a flat average of periods" do
        # One busy slow day and several quiet fast ones: an unweighted mean would
        # sit near the quiet days, a weighted one near the busy day.
        summary_for(2, p95: 1000.0, count: 10_000)
        (3..7).each { |ago| summary_for(ago, p95: 100.0, count: 100) }
        current_day(p95: 100.0)

        comparison = Compare.call(@route)

        assert_operator comparison.baseline_value, :>, 900.0
      end

      test "computes delta, ratio and percent change" do
        history(p95: 200.0)
        current_day(p95: 500.0)

        comparison = Compare.call(@route)

        assert_in_delta 300.0, comparison.delta, 0.01
        assert_in_delta 2.5, comparison.ratio, 0.01
        assert_in_delta 150.0, comparison.percent_change, 0.01
        assert_equal :up, comparison.direction
      end

      test "error_rate metric reads from error and success counts" do
        history(p95: 200.0, days: 5, count: 1000, error_count: 10)
        current_day(p95: 200.0, count: 1000, error_count: 100)

        comparison = Compare.call(@route, metric: :error_rate)

        assert_in_delta 1.0, comparison.baseline_value, 0.01
        assert_in_delta 10.0, comparison.current_value, 0.01
        assert_equal "%", comparison.unit
      end

      # Regression Detection Tests

      test "flags a regression that clears both the ratio and the absolute floor" do
        history(p95: 200.0)
        current_day(p95: 600.0)

        assert_predicate Compare.call(@route), :regression?
      end

      test "does not flag a large ratio below the absolute floor" do
        # 2ms to 4ms doubles, but is not something anyone should be paged about.
        history(p95: 2.0)
        current_day(p95: 4.0)

        comparison = Compare.call(@route)

        assert_operator comparison.ratio, :>=, 2.0
        assert_not_predicate comparison, :regression?
      end

      test "does not flag a large absolute delta below the ratio" do
        history(p95: 4000.0)
        current_day(p95: 4500.0)

        comparison = Compare.call(@route)

        assert_operator comparison.delta, :>, 100.0
        assert_not_predicate comparison, :regression?
      end

      test "does not flag an improvement" do
        history(p95: 900.0)
        current_day(p95: 100.0)

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
        current_day(p95: 900.0)

        comparison = Compare.call(@route)

        assert_not_predicate comparison, :comparable?
        assert_not_predicate comparison, :regression?
      end

      test "requires the configured minimum of baseline periods" do
        # Two days of history, below the default minimum of three.
        summary_for(2, p95: 200.0)
        summary_for(3, p95: 200.0)
        current_day(p95: 900.0)

        comparison = Compare.call(@route)

        assert_predicate comparison, :comparable?
        assert_not_predicate comparison, :sufficient_data?
        assert_not_predicate comparison, :regression?
      end

      test "requires the configured minimum sample count" do
        history(p95: 200.0, days: 5, count: 5)
        current_day(p95: 900.0, count: 5)

        comparison = Compare.call(@route)

        assert_not_predicate comparison, :sufficient_data?
        assert_not_predicate comparison, :regression?
      end

      test "treats a zero baseline as not comparable rather than dividing by it" do
        history(p95: 0.0, days: 5)
        current_day(p95: 900.0)

        comparison = Compare.call(@route)

        assert_not_predicate comparison, :comparable?
        assert_nil comparison.ratio
      end

      test "to_h exposes the full measurement" do
        history(p95: 200.0)
        current_day(p95: 600.0)

        payload = Compare.call(@route).to_h

        assert_equal "RailsPulse::Route", payload[:subject_type]
        assert_equal @route.id, payload[:subject_id]
        assert_equal :p95, payload[:metric]
        assert payload[:regression]
        assert_in_delta 3.0, payload[:ratio], 0.01
      end

      # Scan Tests

      test "scan returns only subjects with sufficient data" do
        history(p95: 200.0)
        current_day(p95: 600.0)

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
