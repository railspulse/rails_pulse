require "test_helper"

module RailsPulse
  module Routes
    module Cards
      class ErrorRatesTest < ActiveSupport::TestCase
        fixtures :rails_pulse_routes, :rails_pulse_summaries

        # Structure Tests

        test "returns hash with required keys" do
          card = RailsPulse::Routes::Cards::ErrorRates.new.to_metric_card

          assert_kind_of Hash, card
          assert_includes card, :id
          assert_includes card, :title
          assert_includes card, :summary
          assert_includes card, :chart_data
          assert_includes card, :trend_icon
          assert_includes card, :trend_amount
          assert_includes card, :trend_text
          assert_includes card, :help_heading
          assert_includes card, :help_text
        end

        test "id is error_rates" do
          card = RailsPulse::Routes::Cards::ErrorRates.new.to_metric_card

          assert_equal "error_rates", card[:id]
        end

        test "chart_color is DEFAULT color" do
          card = RailsPulse::Routes::Cards::ErrorRates.new.to_metric_card

          assert_equal RailsPulse::ChartColors::DEFAULT, card[:chart_color]
        end

        test "context is routes" do
          card = RailsPulse::Routes::Cards::ErrorRates.new.to_metric_card

          assert_equal "routes", card[:context]
        end

        # Calculation Tests

        test "summary format is percentage or —" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(period: 7).to_metric_card

          assert card[:summary] == "—" || card[:summary].match?(/\d+\.\d+% of requests/)
        end

        test "chart_data is a hash" do
          card = RailsPulse::Routes::Cards::ErrorRates.new.to_metric_card

          assert_kind_of Hash, card[:chart_data]
        end

        test "trend_icon is valid" do
          card = RailsPulse::Routes::Cards::ErrorRates.new.to_metric_card

          assert_includes [ "move-right", "trending-up", "trending-down" ], card[:trend_icon]
        end

        test "trend_amount is percentage or —" do
          card = RailsPulse::Routes::Cards::ErrorRates.new.to_metric_card

          assert card[:trend_amount] == "—" || card[:trend_amount].end_with?("%")
        end

        test "trend_text is Compared to last week" do
          card = RailsPulse::Routes::Cards::ErrorRates.new.to_metric_card

          assert_equal "Compared to last week", card[:trend_text]
        end

        # Sparkline Tests

        test "7-day period has correct sparkline size" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(period: 7).to_metric_card

          assert_operator card[:chart_data].size, :>=, 7
          assert_operator card[:chart_data].size, :<=, 8
        end

        test "14-day period has correct sparkline size" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(period: 14).to_metric_card

          assert_operator card[:chart_data].size, :>=, 14
          assert_operator card[:chart_data].size, :<=, 15
        end

        test "30-day period has correct sparkline size" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(period: 30).to_metric_card

          assert_operator card[:chart_data].size, :>=, 30
          assert_operator card[:chart_data].size, :<=, 31
        end

        test "sparkline data has correct structure" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(period: 7).to_metric_card
          card[:chart_data].values.each do |data_point|
            assert_kind_of Hash, data_point
            assert_includes data_point.keys, :value
            assert_kind_of Numeric, data_point[:value]
          end
        end

        test "date labels formatted correctly" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(period: 7).to_metric_card

          card[:chart_data].keys.each do |label|
            assert_match(/[A-Z][a-z]{2} \d{1,2}/, label)
          end
        end

        test "uses hourly summaries for period_type hour" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(period: 1, period_type: "hour").to_metric_card

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
          card = RailsPulse::Routes::Cards::ErrorRates.new(period: 7, period_type: "day").to_metric_card

          # Should have ~7 data points for 7 days
          assert_operator card[:chart_data].size, :>=, 7
          assert_operator card[:chart_data].size, :<=, 8

          # Keys should be date strings when using daily data
          card[:chart_data].keys.each do |label|
            assert_match(/[A-Z][a-z]{2} \d{1,2}/, label)
          end
        end

        # Edge Cases

        test "route-specific mode works" do
          route = rails_pulse_routes(:api_users)
          card = RailsPulse::Routes::Cards::ErrorRates.new(route: route, period: 7).to_metric_card

          assert_kind_of Hash, card
        end

        test "aggregate mode works" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(route: nil, period: 7).to_metric_card

          assert_kind_of Hash, card
        end

        test "respects disabled_tags parameter" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(
            disabled_tags: [ 999999 ],
            period: 7
          ).to_metric_card

          assert_kind_of Hash, card
        end

        test "respects show_non_tagged false" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(
            show_non_tagged: false,
            period: 7
          ).to_metric_card

          assert_kind_of Hash, card
        end

        test "handles periods with limited data" do
          card = RailsPulse::Routes::Cards::ErrorRates.new(period: 90).to_metric_card
          # Should return valid structure regardless of data availability
          assert_kind_of String, card[:summary]
          assert_kind_of String, card[:trend_amount]
          assert_includes [ "move-right", "trending-up", "trending-down" ], card[:trend_icon]
        end
      end
    end
  end
end
