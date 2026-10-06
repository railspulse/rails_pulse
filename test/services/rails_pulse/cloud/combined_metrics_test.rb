require "test_helper"

module RailsPulse
  module Cloud
    class CombinedMetricsTest < ActiveSupport::TestCase
      # Two groups whose raw durations are [10, 20, 30] and [100, 400].
      FIRST = { count: 3, avg_duration: 20.0, min_duration: 10.0, max_duration: 30.0, total_duration: 60.0,
                p50_duration: 20.0, p95_duration: 29.0, p99_duration: 29.8, stddev_duration: 10.0,
                error_count: 1, success_count: 2, status_2xx: 2, status_3xx: 0, status_4xx: 0, status_5xx: 1 }.freeze
      SECOND = { count: 2, avg_duration: 250.0, min_duration: 100.0, max_duration: 400.0, total_duration: 500.0,
                 p50_duration: 250.0, p95_duration: 385.0, p99_duration: 397.0, stddev_duration: Math.sqrt(45_000),
                 error_count: 0, success_count: 2, status_2xx: 1, status_3xx: 0, status_4xx: 1, status_5xx: 0 }.freeze

      # Calculation Tests

      test "counts, totals, min and max combine exactly" do
        combined = CombinedMetrics.of([ FIRST, SECOND ])

        assert_equal 5, combined[:count]
        assert_in_delta 560.0, combined[:total_duration]
        assert_in_delta 112.0, combined[:avg_duration]
        assert_in_delta 10.0, combined[:min_duration]
        assert_in_delta 400.0, combined[:max_duration]
      end

      test "the standard deviation equals the one over every value together" do
        combined = CombinedMetrics.of([ FIRST, SECOND ])

        assert_in_delta Statistics.calculate_stddev([ 10, 20, 30, 100, 400 ], 112.0), combined[:stddev_duration], 0.001
      end

      test "percentiles are weighted by count" do
        combined = CombinedMetrics.of([ FIRST, SECOND ])

        assert_in_delta ((20.0 * 3) + (250.0 * 2)) / 5, combined[:p50_duration]
      end

      test "status counts add up" do
        combined = CombinedMetrics.of([ FIRST, SECOND ])

        assert_equal 1, combined[:error_count]
        assert_equal 3, combined[:status_2xx]
        assert_equal 1, combined[:status_4xx]
      end

      test "only the counts asked for are included" do
        assert_empty CombinedMetrics.of([ FIRST, SECOND ], counts: []).keys & CombinedMetrics::COUNTS
      end

      # Edge Cases

      test "a row with no percentile is left out of that percentile's weighting" do
        combined = CombinedMetrics.of([ FIRST, SECOND.merge(p99_duration: nil) ])

        assert_in_delta 29.8, combined[:p99_duration]
      end

      test "empty rows are skipped and an empty set has a count of zero" do
        assert_equal({ count: 0 }, CombinedMetrics.of([]))
        assert_equal 3, CombinedMetrics.of([ FIRST, { count: 0 } ])[:count]
      end

      test "a single value has no standard deviation" do
        single = { count: 1, avg_duration: 5.0, min_duration: 5.0, max_duration: 5.0, total_duration: 5.0 }

        assert_nil CombinedMetrics.of([ single ])[:stddev_duration]
      end
    end
  end
end
