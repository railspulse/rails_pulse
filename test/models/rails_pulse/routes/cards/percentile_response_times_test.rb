require "test_helper"

module RailsPulse
  module Routes
    module Cards
      class PercentileResponseTimesTest < ActiveSupport::TestCase
        fixtures :rails_pulse_routes, :rails_pulse_summaries

        test "returns hash with required keys" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new.to_metric_card

          assert_kind_of Hash, card
          assert_includes card.keys, :id
          assert_includes card.keys, :title
          assert_includes card.keys, :summary
          assert_includes card.keys, :chart_data
          assert_includes card.keys, :trend_icon
          assert_includes card.keys, :trend_amount
          assert_includes card.keys, :trend_text
          assert_includes card.keys, :help_heading
          assert_includes card.keys, :help_text
          assert_includes card.keys, :chart_color
          assert_includes card.keys, :context
        end

        test "id is percentile_response_times" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new.to_metric_card

          assert_equal "percentile_response_times", card[:id]
        end

        test "chart_color is P95 color" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new.to_metric_card

          assert_equal RailsPulse::ChartColors::P95, card[:chart_color]
        end

        test "context is routes" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new.to_metric_card

          assert_equal "routes", card[:context]
        end

        test "chart_data is a hash" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new.to_metric_card

          assert_kind_of Hash, card[:chart_data]
        end

        test "summary has ms suffix or is —" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(period: 7).to_metric_card

          assert card[:summary] == "—" || card[:summary].match?(/\d+ ms/)
        end

        test "trend_amount ends with % or is —" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new.to_metric_card

          assert card[:trend_amount] == "—" || card[:trend_amount].end_with?("%")
        end

        test "trend_text reflects the selected period" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new.to_metric_card

          assert_equal "Compared to previous 7 days", card[:trend_text]
        end

        test "trend_icon is valid" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new.to_metric_card

          assert_includes [ "move-right", "trending-up", "trending-down" ], card[:trend_icon]
        end

        test "calculates for 7-day period" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(period: 7).to_metric_card

          assert_operator card[:chart_data].size, :>=, 7
          assert_operator card[:chart_data].size, :<=, 8
        end

        test "calculates for 14-day period" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(period: 14).to_metric_card

          assert_operator card[:chart_data].size, :>=, 14
          assert_operator card[:chart_data].size, :<=, 15
        end

        test "calculates for 30-day period" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(period: 30).to_metric_card

          assert_operator card[:chart_data].size, :>=, 30
          assert_operator card[:chart_data].size, :<=, 31
        end

        test "sparkline data has correct structure" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(period: 7).to_metric_card
          card[:chart_data].values.each do |data_point|
            assert_kind_of Hash, data_point
            assert_includes data_point.keys, :value
            assert_kind_of Numeric, data_point[:value]
          end
        end

        test "date labels formatted correctly" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(period: 7).to_metric_card

          card[:chart_data].keys.each do |label|
            assert_match(/[A-Z][a-z]{2} \d{1,2}/, label)
          end
        end

        test "route-specific mode filters by route id" do
          route = rails_pulse_routes(:api_users)
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: route, period: 7).to_metric_card

          assert_kind_of Hash, card
        end

        test "aggregate mode includes all routes" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil, period: 7).to_metric_card

          assert_kind_of Hash, card
        end

        test "respects disabled_tags parameter" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(
            disabled_tags: [ 999999 ],
            period: 7
          ).to_metric_card

          assert_kind_of Hash, card
        end

        test "respects show_non_tagged false" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(
            show_non_tagged: false,
            period: 7
          ).to_metric_card

          assert_kind_of Hash, card
        end

        test "handles periods with limited data" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(period: 90).to_metric_card
          # Should return valid structure regardless of data availability
          assert_kind_of String, card[:summary]
          # Trend is hidden for periods > 14 days
          assert_nil card[:trend_amount]
          assert_nil card[:trend_icon]
        end

        test "uses hourly summaries for period_type hour" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(period: 1, period_type: "hour").to_metric_card

          # Should have ~24 data points for 1 day
          assert_operator card[:chart_data].size, :>=, 24
          assert_operator card[:chart_data].size, :<=, 25

          # Keys should be timestamps in milliseconds when using hourly data
          card[:chart_data].keys.each do |key|
            assert_kind_of Integer, key
            assert_operator key, :>, 1000000000000 # Millisecond timestamp
          end
        end

        test "uses daily summaries for period_type day" do
          card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(period: 7, period_type: "day").to_metric_card

          # Should have ~7 data points for 7 days
          assert_operator card[:chart_data].size, :>=, 7
          assert_operator card[:chart_data].size, :<=, 8

          # Keys should be date strings when using daily data
          card[:chart_data].keys.each do |label|
            assert_match(/[A-Z][a-z]{2} \d{1,2}/, label)
          end
        end
      end
    end
  end
end
