require "test_helper"

module RailsPulse
  module Operations
    class ChangePointTest < ActiveSupport::TestCase
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

      def day_summary(days_ago, p95:, count: 500)
        period_start = (@now - days_ago.days).beginning_of_day
        create_summary(period_start, period_start.end_of_day, "day", p95, count)
      end

      def hour_summary(hours_ago, p95:, count: 100)
        period_start = (@now - hours_ago.hours).beginning_of_hour
        create_summary(period_start, period_start.end_of_hour, "hour", p95, count)
      end

      def create_summary(period_start, period_end, period_type, p95, count)
        RailsPulse::Summary.create!(
          summarizable_type: "RailsPulse::Route",
          summarizable_id:   @route.id,
          period_type:       period_type,
          period_start:      period_start,
          period_end:        period_end,
          count:             count,
          avg_duration:      p95 * 0.6,
          p50_duration:      p95 * 0.5,
          p95_duration:      p95,
          p99_duration:      p95 * 1.2,
          error_count:       0,
          success_count:     count
        )
      end

      # Structure Tests

      test "returns nil when there is no series at all" do
        assert_nil ChangePoint.call(@route)
      end

      test "returns nil when the series is too short to split" do
        day_summary(1, p95: 200.0)
        day_summary(2, p95: 200.0)

        assert_nil ChangePoint.call(@route)
      end

      # Detection Tests

      test "finds the day a metric stepped up" do
        # Fast until 5 days ago, slow from 4 days ago onward.
        (5..9).each { |ago| day_summary(ago, p95: 100.0) }
        (0..4).each { |ago| day_summary(ago, p95: 900.0) }

        result = ChangePoint.call(@route)

        assert_not_nil result
        assert_equal (@now - 4.days).beginning_of_day, result.at
        assert_in_delta 100.0, result.before_value, 0.01
        assert_in_delta 900.0, result.after_value, 0.01
        assert_in_delta 9.0, result.ratio, 0.01
      end

      test "finds a step down as readily as a step up" do
        (5..9).each { |ago| day_summary(ago, p95: 900.0) }
        (0..4).each { |ago| day_summary(ago, p95: 100.0) }

        result = ChangePoint.call(@route)

        assert_equal (@now - 4.days).beginning_of_day, result.at
        assert_operator result.delta, :<, 0
      end

      test "picks the largest step when a series moves more than once" do
        (7..9).each { |ago| day_summary(ago, p95: 100.0) }
        (4..6).each { |ago| day_summary(ago, p95: 150.0) }
        (0..3).each { |ago| day_summary(ago, p95: 2000.0) }

        result = ChangePoint.call(@route)

        assert_equal (@now - 3.days).beginning_of_day, result.at
      end

      test "reports counts on each side of the split" do
        (5..9).each { |ago| day_summary(ago, p95: 100.0, count: 10) }
        (0..4).each { |ago| day_summary(ago, p95: 900.0, count: 100) }

        result = ChangePoint.call(@route)

        assert_equal 50,  result.before_count
        assert_equal 500, result.after_count
      end

      # Granularity Tests

      test "uses hourly precision inside the retained hourly window" do
        (0..23).each { |ago| hour_summary(ago, p95: ago < 12 ? 900.0 : 100.0) }

        result = ChangePoint.call(@route, range: 2.days.ago..@now)

        assert_equal "hour", result.granularity
        assert_predicate result, :hourly?
        assert_equal (@now - 11.hours).beginning_of_hour, result.at
      end

      test "falls back to day granularity outside the hourly window" do
        (5..9).each { |ago| day_summary(ago, p95: 100.0) }
        (0..4).each { |ago| day_summary(ago, p95: 900.0) }

        result = ChangePoint.call(@route)

        assert_equal "day", result.granularity
        assert_not_predicate result, :hourly?
      end

      test "prefers day granularity over a too-short hourly series" do
        # Only two hourly periods survive — not enough to split — but a full day
        # series is available and should be used rather than returning nil.
        hour_summary(0, p95: 900.0)
        hour_summary(1, p95: 900.0)
        (5..9).each { |ago| day_summary(ago, p95: 100.0) }
        (0..4).each { |ago| day_summary(ago, p95: 900.0) }

        result = ChangePoint.call(@route)

        assert_equal "day", result.granularity
      end

      # Edge Cases

      test "returns nil for a perfectly flat series" do
        (0..9).each { |ago| day_summary(ago, p95: 200.0) }

        # Every split produces the same means, so no split separates anything.
        assert_nil ChangePoint.call(@route)
      end

      test "to_h exposes the estimate and its precision" do
        (5..9).each { |ago| day_summary(ago, p95: 100.0) }
        (0..4).each { |ago| day_summary(ago, p95: 900.0) }

        payload = ChangePoint.call(@route).to_h

        assert_equal "day", payload[:granularity]
        assert_in_delta 800.0, payload[:delta], 0.01
      end
    end
  end
end
