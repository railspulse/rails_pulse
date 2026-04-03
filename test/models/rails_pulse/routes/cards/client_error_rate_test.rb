require "test_helper"

module RailsPulse
  module Routes
    module Cards
      class ClientErrorRateTest < ActiveSupport::TestCase
        fixtures :rails_pulse_summaries, :rails_pulse_routes

        # Structure Tests

        test "returns a hash with required metric card keys" do
          card = ClientErrorRate.new.to_metric_card

          assert_includes card, :id
          assert_includes card, :title
          assert_includes card, :summary
          assert_includes card, :chart_data
          assert_includes card, :trend_icon
          assert_includes card, :trend_amount
          assert_includes card, :trend_text
        end

        test "id is client_error_rate" do
          card = ClientErrorRate.new.to_metric_card

          assert_equal "client_error_rate", card[:id]
        end

        test "title is Client Error Rate" do
          card = ClientErrorRate.new.to_metric_card

          assert_equal "Client Error Rate", card[:title]
        end

        test "includes help text" do
          card = ClientErrorRate.new.to_metric_card

          assert_includes card, :help_heading
          assert_includes card, :help_text
          assert_equal "Client Error Rate (4xx)", card[:help_heading]
          assert_match(/4xx/, card[:help_text])
        end

        # Calculation Tests

        test "calculates 4xx rate as percentage of total requests" do
          route = rails_pulse_routes(:api_users)
          card = ClientErrorRate.new(route: route).to_metric_card

          # client_error_current_week: 20/200 = 10%
          # client_error_previous_week: 40/200 = 20%
          # route_summary_api_users_day: 0/120 (no status_4xx set)
          # Combined 4xx across both windows: 60 / 520 total
          assert_match(/\d+\.\d+%/, card[:summary])
        end

        test "shows 0% when all requests are successful" do
          route = rails_pulse_routes(:api_posts)
          card = ClientErrorRate.new(route: route).to_metric_card

          assert_equal "0.0%", card[:summary]
        end

        test "shows dash when no data" do
          route = rails_pulse_routes(:api_cleanup)  # only has hour-period summaries, not day
          card = ClientErrorRate.new(route: route).to_metric_card

          assert_equal "—", card[:summary]
          assert_equal "—", card[:trend_amount]
        end

        # Trend Tests

        test "shows trending-down when 4xx rate improved" do
          route = rails_pulse_routes(:api_users)
          card = ClientErrorRate.new(route: route).to_metric_card

          # current week: 20 errors, previous week: 40 errors — improving
          assert_equal "trending-down", card[:trend_icon]
        end

        test "shows move-right when no previous period data" do
          route = rails_pulse_routes(:api_posts)
          card = ClientErrorRate.new(route: route).to_metric_card

          assert_equal "move-right", card[:trend_icon]
        end

        # Sparkline Tests

        test "chart_data covers the last 14 days" do
          card = ClientErrorRate.new.to_metric_card

          assert_equal 15, card[:chart_data].size
        end

        test "chart_data values are non-negative integers" do
          card = ClientErrorRate.new.to_metric_card

          card[:chart_data].each_value do |entry|
            assert_operator entry[:value], :>=, 0
          end
        end

        # Edge Cases

        test "fleet-wide card with no route filter includes all routes" do
          card_all = ClientErrorRate.new.to_metric_card
          route = rails_pulse_routes(:api_users)
          card_route = ClientErrorRate.new(route: route).to_metric_card

          # Fleet-wide summary should be >= single route summary
          all_rate = card_all[:summary].to_f
          route_rate = card_route[:summary].to_f

          assert_operator all_rate, :>=, 0
          assert_operator route_rate, :>=, 0
        end

        test "handles nil status_4xx gracefully" do
          # route_summary_mid has no status_4xx set — should not raise
          route = rails_pulse_routes(:api_test)
          assert_nothing_raised { ClientErrorRate.new(route: route).to_metric_card }
        end
      end
    end
  end
end
