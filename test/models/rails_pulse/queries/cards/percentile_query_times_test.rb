require "test_helper"

module RailsPulse
  module Queries
    module Cards
      class PercentileQueryTimesTest < ActiveSupport::TestCase
        fixtures :rails_pulse_queries, :rails_pulse_summaries

        def setup
          ENV["TEST_TYPE"] = "functional"
          super
        end

        # Structure Tests

        test "returns hash with required keys" do
          card = PercentileQueryTimes.new

          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "percentile_query_times", result[:id]
          assert_equal "queries", result[:context]
          assert_equal "P95 Query Time", result[:title]
          assert_includes result, :summary
          assert_includes result, :chart_data
          assert_includes result, :chart_color
          assert_includes result, :trend_icon
          assert_includes result, :trend_amount
          assert_includes result, :trend_text
          assert_includes result, :help_heading
          assert_includes result, :help_text
        end

        test "summary is formatted as duration" do
          card = PercentileQueryTimes.new

          result = card.to_metric_card

          assert_match(/\d+ ms/, result[:summary])
        end

        test "chart_data is a hash" do
          card = PercentileQueryTimes.new

          result = card.to_metric_card

          assert_kind_of Hash, result[:chart_data]
        end

        test "has correct chart color" do
          card = PercentileQueryTimes.new

          result = card.to_metric_card

          assert_equal RailsPulse::ChartColors::P95, result[:chart_color]
        end

        # Period Type Tests

        test "accepts day period_type" do
          card = PercentileQueryTimes.new(period: 7, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end

        test "accepts hour period_type" do
          card = PercentileQueryTimes.new(period: 1, period_type: "hour")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end

        test "sparkline uses date labels for day period" do
          card = PercentileQueryTimes.new(period: 7, period_type: "day")

          result = card.to_metric_card
          sparkline_data = result[:chart_data]

          # Keys should be date strings like "Jan 1"
          unless sparkline_data.empty?
            first_key = sparkline_data.keys.first

            assert_kind_of String, first_key
          end
        end

        test "sparkline uses millisecond timestamps for hour period" do
          card = PercentileQueryTimes.new(period: 1, period_type: "hour")

          result = card.to_metric_card
          sparkline_data = result[:chart_data]

          # Keys should be integers (timestamps in milliseconds)
          unless sparkline_data.empty?
            first_key = sparkline_data.keys.first

            assert_kind_of Integer, first_key
          end
        end

        # Query Filtering Tests

        test "accepts query parameter" do
          query = rails_pulse_queries(:simple_query)
          card = PercentileQueryTimes.new(query: query, period: 7, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end

        test "accepts nil query parameter" do
          card = PercentileQueryTimes.new(query: nil, period: 7, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end

        # Tag Filter Tests

        test "accepts disabled_tags parameter" do
          card = PercentileQueryTimes.new(disabled_tags: [ "slow" ], period: 7, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end

        test "accepts show_non_tagged parameter" do
          card = PercentileQueryTimes.new(show_non_tagged: false, period: 7, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end

        test "accepts nil disabled_tags" do
          card = PercentileQueryTimes.new(disabled_tags: nil, period: 7, period_type: "day")

          assert_nothing_raised do
            card.to_metric_card
          end
        end

        test "accepts empty disabled_tags array" do
          card = PercentileQueryTimes.new(disabled_tags: [], period: 7, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end

        # Trend Icon Tests

        test "trend_icon is one of the valid values" do
          card = PercentileQueryTimes.new

          result = card.to_metric_card

          assert_includes [ "trending-up", "trending-down", "move-right" ], result[:trend_icon]
        end

        test "trend_amount is formatted with percentage" do
          card = PercentileQueryTimes.new

          result = card.to_metric_card

          # Should be a percentage string like "50.0%"
          assert_match(/\d+(\.\d+)?%/, result[:trend_amount])
        end

        # Edge Cases

        test "handles very large period values" do
          card = PercentileQueryTimes.new(period: 365, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end

        test "handles period of 0" do
          card = PercentileQueryTimes.new(period: 0, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end
      end
    end
  end
end
