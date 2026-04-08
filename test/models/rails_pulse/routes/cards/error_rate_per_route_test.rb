require "test_helper"

module RailsPulse
  module Routes
    module Cards
      class ErrorRatePerRouteTest < ActiveSupport::TestCase
        fixtures :rails_pulse_routes

        def setup
          ENV["TEST_TYPE"] = "functional"
          super

          @route = rails_pulse_routes(:api_test)

          RailsPulse::Summary.delete_all

          @now = Time.current
          travel_to @now
        end

        def teardown
          travel_back
          super
        end

        # Structure Tests

        test "returns hash with required metric card keys" do
          card = ErrorRatePerRoute.new.to_metric_card

          assert_kind_of Hash, card
          assert_includes card, :id
          assert_includes card, :title
          assert_includes card, :summary
          assert_includes card, :chart_data
          assert_includes card, :trend_icon
          assert_includes card, :trend_amount
          assert_includes card, :trend_text
        end

        test "id is error_rate_per_route" do
          card = ErrorRatePerRoute.new.to_metric_card

          assert_equal "error_rate_per_route", card[:id]
        end

        test "title is Error Rate Per Route" do
          card = ErrorRatePerRoute.new.to_metric_card

          assert_equal "Error Rate Per Route", card[:title]
        end

        test "context is routes" do
          card = ErrorRatePerRoute.new.to_metric_card

          assert_equal "routes", card[:context]
        end

        test "includes help text about 5xx errors" do
          card = ErrorRatePerRoute.new.to_metric_card

          assert_includes card, :help_heading
          assert_includes card, :help_text
          assert_equal "Server Error Rate (5xx)", card[:help_heading]
          assert_match(/5xx/, card[:help_text])
          assert_match(/Server errors/, card[:help_text])
        end

        test "trend_text mentions last week comparison" do
          card = ErrorRatePerRoute.new.to_metric_card

          assert_equal "Compared to last week", card[:trend_text]
        end

        # Calculation Tests

        test "calculates error rate as percentage of total requests" do
          # Current window: 10 errors out of 100 requests = 10%
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 10)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          assert_equal "10.0%", card[:summary]
        end

        test "only counts 5xx errors not 4xx errors" do
          # 5xx errors: 10, 4xx errors: 20 (should be excluded), total: 100
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 10, status_4xx: 20)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          # Should only count 5xx: 10/100 = 10%, not 30/100 = 30%
          assert_equal "10.0%", card[:summary]
        end

        test "aggregates error counts across multiple days" do
          # Day 1: 5 errors, 50 requests
          create_route_summary(route: @route, days_ago: 3, count: 50, error_count: 5)
          # Day 2: 10 errors, 100 requests
          create_route_summary(route: @route, days_ago: 5, count: 100, error_count: 10)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          # Total: 15 errors / 150 requests = 10%
          assert_equal "10.0%", card[:summary]
        end

        test "filters to specific route when route parameter provided" do
          route2 = rails_pulse_routes(:api_posts)

          # Route 1: 10% error rate
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 10)
          # Route 2: 20% error rate (should be excluded)
          create_route_summary(route: route2, days_ago: 3, count: 100, error_count: 20)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          # Should only show route 1's rate
          assert_equal "10.0%", card[:summary]
        end

        test "aggregates all routes when route is nil" do
          route2 = rails_pulse_routes(:api_posts)

          # Route 1: 10 errors, 100 requests
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 10)
          # Route 2: 20 errors, 100 requests
          create_route_summary(route: route2, days_ago: 3, count: 100, error_count: 20)

          card = ErrorRatePerRoute.new(route: nil).to_metric_card

          # Total: 30 errors / 200 requests = 15%
          assert_equal "15.0%", card[:summary]
        end

        test "rounds error rate to 2 decimal places" do
          # 1 error out of 3 requests = 33.333...%
          create_route_summary(route: @route, days_ago: 3, count: 3, error_count: 1)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          assert_equal "33.33%", card[:summary]
        end

        # Trend Calculation Tests

        test "trend shows trending-up when errors increase" do
          # Current window (last 7 days): 20 errors
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 20)

          # Previous window (8-14 days ago): 10 errors
          create_route_summary(route: @route, days_ago: 10, count: 100, error_count: 10)

          card = ErrorRatePerRoute.new(route: @route, period: 7).to_metric_card

          # Errors increased from 10 to 20 = +100%
          assert_equal "trending-up", card[:trend_icon]
          assert_equal "100.0%", card[:trend_amount]
        end

        test "trend shows trending-down when errors decrease" do
          # Current window: 10 errors
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 10)

          # Previous window: 20 errors
          create_route_summary(route: @route, days_ago: 10, count: 100, error_count: 20)

          card = ErrorRatePerRoute.new(route: @route, period: 7).to_metric_card

          # Errors decreased from 20 to 10 = -50%
          assert_equal "trending-down", card[:trend_icon]
          assert_equal "50.0%", card[:trend_amount]
        end

        test "trend shows move-right when errors stay the same" do
          # Current window: 10 errors
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 10)

          # Previous window: 10 errors
          create_route_summary(route: @route, days_ago: 10, count: 100, error_count: 10)

          card = ErrorRatePerRoute.new(route: @route, period: 7).to_metric_card

          # No change
          assert_equal "move-right", card[:trend_icon]
          assert_match(/0/, card[:trend_amount])
        end

        test "trend compares error counts not error rates" do
          # Current window: 10 errors, 100 requests (10% rate)
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 10)

          # Previous window: 5 errors, 25 requests (20% rate)
          create_route_summary(route: @route, days_ago: 10, count: 25, error_count: 5)

          card = ErrorRatePerRoute.new(route: @route, period: 7).to_metric_card

          # Should compare counts (10 vs 5 = +100%), not rates (10% vs 20%)
          assert_equal "trending-up", card[:trend_icon]
          assert_equal "100.0%", card[:trend_amount]
        end

        # Sparkline Tests

        test "chart_data covers full 14-day period" do
          card = ErrorRatePerRoute.new.to_metric_card

          # Should have 15 days of data (14 days ago through today)
          assert_equal 15, card[:chart_data].size
        end

        test "chart_data has string date labels" do
          card = ErrorRatePerRoute.new.to_metric_card

          card[:chart_data].each_key do |label|
            assert_kind_of String, label
            # Should be in format like "Jan 1"
            assert_match(/\w+ \d+/, label)
          end
        end

        test "chart_data values are hashes with value key" do
          card = ErrorRatePerRoute.new.to_metric_card

          card[:chart_data].each_value do |entry|
            assert_kind_of Hash, entry
            assert_includes entry.keys, :value
            assert_kind_of Integer, entry[:value]
          end
        end

        test "chart_data values are non-negative integers" do
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 10)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          card[:chart_data].each_value do |entry|
            assert_operator entry[:value], :>=, 0
          end
        end

        test "chart_data shows error counts by day" do
          # Day 1: 5 errors
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 5)
          # Day 2: 10 errors
          create_route_summary(route: @route, days_ago: 5, count: 100, error_count: 10)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          # Should have 5 and 10 in the sparkline data
          values = card[:chart_data].values.map { |v| v[:value] }

          assert_includes values, 5
          assert_includes values, 10
        end

        test "chart_data pads missing days with zeros" do
          # Only create data for 1 day
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 10)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          # Should have 14 days of zeros plus 1 day with 10
          zero_count = card[:chart_data].values.count { |v| v[:value] == 0 }

          assert_operator zero_count, :>, 10
        end

        # Tag Filtering Tests

        test "accepts disabled_tags parameter" do
          # Tag filtering is applied via with_tag_filters scope on Summary model
          # Just verify it accepts the parameter without error
          card = ErrorRatePerRoute.new(
            route: @route,
            disabled_tags: [ "api" ]
          ).to_metric_card

          assert_kind_of Hash, card
        end

        test "accepts show_non_tagged parameter" do
          # Tag filtering is applied via with_tag_filters scope on Summary model
          # Just verify it accepts the parameter without error
          card = ErrorRatePerRoute.new(
            route: @route,
            show_non_tagged: false
          ).to_metric_card

          assert_kind_of Hash, card
        end

        # Edge Cases

        test "handles route with no data" do
          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          assert_equal "—", card[:summary]
          assert_equal "move-right", card[:trend_icon]
          assert_equal "—", card[:trend_amount]
        end

        test "handles route with zero requests" do
          create_route_summary(route: @route, days_ago: 3, count: 0, error_count: 0)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          assert_equal "—", card[:summary]
        end

        test "handles route with all successful requests" do
          # 0 errors out of 100 requests
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 0)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          assert_equal "0.0%", card[:summary]
        end

        test "handles 100% error rate" do
          # All requests fail
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 100)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          assert_equal "100.0%", card[:summary]
        end

        test "handles only current window data" do
          # Only data in current window, none in previous
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 15)

          card = ErrorRatePerRoute.new(route: @route, period: 7).to_metric_card

          assert_equal "15.0%", card[:summary]
          # Trend should show move-right since no previous data
          assert_equal "move-right", card[:trend_icon]
        end

        test "handles only previous window data" do
          # Only data in previous window, none in current
          create_route_summary(route: @route, days_ago: 10, count: 100, error_count: 20)

          card = ErrorRatePerRoute.new(route: @route, period: 7).to_metric_card

          # Should still show overall rate
          assert_equal "20.0%", card[:summary]
          # Trend should show trending-down (current 0 vs previous 20)
          assert_equal "trending-down", card[:trend_icon]
        end

        test "handles large error counts" do
          create_route_summary(route: @route, days_ago: 3, count: 10000, error_count: 5000)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          assert_equal "50.0%", card[:summary]
        end

        test "handles very small error rates" do
          # 1 error in 10000 requests = 0.01%
          create_route_summary(route: @route, days_ago: 3, count: 10000, error_count: 1)

          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          assert_equal "0.01%", card[:summary]
        end

        test "period parameter controls window size" do
          # Create data 3 days ago (in current window)
          create_route_summary(route: @route, days_ago: 3, count: 100, error_count: 10)
          # Create data 20 days ago (outside 14-day window)
          create_route_summary(route: @route, days_ago: 20, count: 100, error_count: 15)

          # With period: 7, range is last 14 days (includes 3 days ago, excludes 20 days ago)
          card_7day = ErrorRatePerRoute.new(route: @route, period: 7).to_metric_card
          # 10 errors / 100 requests = 10%
          assert_equal "10.0%", card_7day[:summary]

          # With period: 14, range is last 28 days (includes both)
          card_14day = ErrorRatePerRoute.new(route: @route, period: 14).to_metric_card
          # 25 errors / 200 requests = 12.5%
          assert_equal "12.5%", card_14day[:summary]
        end

        test "chart_color is DEFAULT" do
          card = ErrorRatePerRoute.new.to_metric_card

          assert_equal RailsPulse::ChartColors::DEFAULT, card[:chart_color]
        end

        test "only uses day period type" do
          # This card doesn't support hourly periods, only daily
          card = ErrorRatePerRoute.new(route: @route).to_metric_card

          # Should complete without error
          assert_kind_of Hash, card
        end

        private

        def create_route_summary(route:, days_ago:, count:, error_count:, status_4xx: 0)
          period_start = days_ago.days.ago.beginning_of_day

          RailsPulse::Summary.create!(
            summarizable_type: "RailsPulse::Route",
            summarizable_id: route.id,
            period_start: period_start,
            period_end: period_start.end_of_day,
            period_type: "day",
            count: count,
            error_count: error_count,
            status_4xx: status_4xx,
            avg_duration: 100.0,
            p50_duration: 80.0,
            p95_duration: 150.0,
            p99_duration: 200.0
          )
        end
      end
    end
  end
end
