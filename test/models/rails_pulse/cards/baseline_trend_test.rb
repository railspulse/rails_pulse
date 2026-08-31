require "test_helper"

module RailsPulse
  module Cards
    # Detail-page cards compare a subject against its own history instead of
    # against the immediately preceding window. Index cards can't — they
    # aggregate across every subject — so they keep the old arrow.
    class BaselineTrendTest < ActiveSupport::TestCase
      fixtures :rails_pulse_routes, :rails_pulse_queries

      def setup
        @route = rails_pulse_routes(:api_users)
        @now   = Time.utc(2026, 6, 15, 12, 0, 0)
        travel_to @now
        RailsPulse::Summary.delete_all
      end

      def teardown
        travel_back
      end

      def summary_for(days_ago, p95:, count: 500, error_count: 0, subject: nil)
        record = subject || @route
        period_start = (@now - days_ago.days).beginning_of_day

        RailsPulse::Summary.create!(
          summarizable_type: record.class.name,
          summarizable_id:   record.id,
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

      def steady(p95: 200.0, days: 10, subject: nil, count: 500, error_count: 0)
        (2..(days + 1)).each do |ago|
          summary_for(ago, p95: p95, subject: subject, count: count, error_count: error_count)
        end
      end

      def card_for(route)
        RailsPulse::Routes::Cards::PercentileResponseTimes
          .new(route: route, period: 14, period_type: "day")
          .to_metric_card
      end

      # Structure Tests

      test "a detail card compares against the subject's own normal" do
        steady(p95: 200.0)
        summary_for(1, p95: 800.0)

        card = card_for(@route)

        assert_equal "trending-up", card[:trend_icon]
        assert_includes card[:trend_text], "28-day normal"
      end

      test "an index card keeps the period-over-period comparison" do
        steady(p95: 200.0)
        summary_for(1, p95: 800.0)

        # No route means every route aggregated, so there is no single history.
        card = RailsPulse::Routes::Cards::PercentileResponseTimes
          .new(period: 14, period_type: "day")
          .to_metric_card

        assert_includes card[:trend_text], "Compared to previous"
        assert_not_includes card[:trend_text], "normal"
      end

      test "an improvement trends down" do
        steady(p95: 900.0)
        summary_for(1, p95: 100.0)

        assert_equal "trending-down", card_for(@route)[:trend_icon]
      end

      test "a steady metric does not trend" do
        steady(p95: 200.0)
        summary_for(1, p95: 200.0)

        assert_equal "move-right", card_for(@route)[:trend_icon]
      end

      # Change Point Tests

      test "a regression names roughly when it started" do
        steady(p95: 200.0)
        summary_for(1, p95: 900.0)

        assert_includes card_for(@route)[:trend_text], "since"
      end

      test "a healthy metric does not name a change point" do
        steady(p95: 200.0)
        summary_for(1, p95: 205.0)

        assert_not_includes card_for(@route)[:trend_text], "since"
      end

      # Fallback Tests

      test "falls back to period-over-period without enough history" do
        # Two days of history is below the minimum for a baseline.
        summary_for(1, p95: 900.0)
        summary_for(2, p95: 200.0)

        assert_includes card_for(@route)[:trend_text], "Compared to previous"
      end

      test "falls back when the subject has no summaries at all" do
        assert_includes card_for(@route)[:trend_text], "Compared to previous"
      end

      test "one subject's history does not leak into another's" do
        other = rails_pulse_routes(:api_posts)
        steady(p95: 200.0, subject: other)
        summary_for(1, p95: 900.0, subject: other)

        # @route itself has no history, so it must fall back rather than borrow.
        assert_includes card_for(@route)[:trend_text], "Compared to previous"
      end

      # Other Cards

      test "the query card compares against the query's own normal" do
        query = rails_pulse_queries(:simple_query)
        steady(p95: 40.0, subject: query)
        summary_for(1, p95: 200.0, subject: query)

        card = RailsPulse::Queries::Cards::PercentileQueryTimes
          .new(query: query, period: 14, period_type: "day")
          .to_metric_card

        assert_includes card[:trend_text], "28-day normal"
      end

      test "the error rate card compares rates, not raw counts" do
        steady(p95: 200.0, count: 1000, error_count: 5)
        summary_for(1, p95: 200.0, count: 1000, error_count: 200)

        card = RailsPulse::Routes::Cards::ErrorRates
          .new(route: @route, period: 14, period_type: "day")
          .to_metric_card

        assert_equal "trending-up", card[:trend_icon]
        assert_includes card[:trend_text], "28-day normal"
      end
    end
  end
end
