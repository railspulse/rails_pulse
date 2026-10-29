require "test_helper"

module RailsPulse
  module Exceptions
    module Cards
      class TotalOccurrencesTest < ActiveSupport::TestCase
        def setup
          ENV["TEST_TYPE"] = "functional"
          super

          travel_to Time.current
          RailsPulse::Summary.delete_all
        end

        def teardown
          travel_back
          super
        end

        # Structure Tests

        test "returns a metric card hash" do
          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "exceptions_total_occurrences", result[:id]
          assert_equal "Occurrences", result[:title]
        end

        # Calculation Tests

        test "headline covers the selected window only, not the previous one" do
          create_rollup_summary(3.days.ago, count: 10)
          create_rollup_summary(10.days.ago, count: 500)

          result = card.to_metric_card

          assert_equal "10 raised", result[:summary]
          assert_equal "trending-down", result[:trend_icon]
        end

        test "headline sums every period in the window" do
          create_rollup_summary(2.days.ago, count: 4)
          create_rollup_summary(3.days.ago, count: 6)

          assert_equal "10 raised", card.to_metric_card[:summary]
        end

        # Edge Cases

        test "headline is zero with no data" do
          assert_equal "0 raised", card.to_metric_card[:summary]
        end

        private

        def card(period: 7, period_type: "day")
          RailsPulse::Exceptions::Cards::TotalOccurrences.new(period: period, period_type: period_type)
        end

        def create_rollup_summary(period_start, count:)
          start = period_start.beginning_of_day

          RailsPulse::Summary.create!(
            summarizable_type: "RailsPulse::ExceptionGroup",
            summarizable_id: 0,
            period_type: "day",
            period_start: start,
            period_end: start + 1.day,
            count: count
          )
        end
      end
    end
  end
end
