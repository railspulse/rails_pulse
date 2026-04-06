require "test_helper"

module RailsPulse
  module Queries
    module Cards
      class DatabaseLoadTest < ActiveSupport::TestCase
        fixtures :rails_pulse_summaries, :rails_pulse_routes, :rails_pulse_queries

        # Structure Tests

        test "returns a hash with required metric card keys" do
          card = DatabaseLoad.new.to_metric_card

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

        test "id is database_load" do
          card = DatabaseLoad.new.to_metric_card

          assert_equal "database_load", card[:id]
        end

        test "title is Database Load" do
          card = DatabaseLoad.new.to_metric_card

          assert_equal "Database Load", card[:title]
        end

        # Calculation Tests

        test "calculates DB percentage as query time divided by request time" do
          # Delete all existing summaries to avoid conflicts
          RailsPulse::Summary.delete_all

          # Create route summaries (total request time)
          route = rails_pulse_routes(:api_users)
          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 5.days.ago.beginning_of_day,
            period_end: 5.days.ago.end_of_day,
            count: 100,
            total_duration: 10000.0  # 10 seconds total request time
          )

          # Create query summaries (DB time)
          query = rails_pulse_queries(:complex_query)
          RailsPulse::Summary.create!(
            summarizable: query,
            period_type: "day",
            period_start: 5.days.ago.beginning_of_day,
            period_end: 5.days.ago.end_of_day,
            count: 500,
            total_duration: 3000.0  # 3 seconds total DB time
          )

          card = DatabaseLoad.new.to_metric_card

          # 3000 / 10000 = 30%
          assert_equal "30.0%", card[:summary]
        end

        test "shows dash when no route data exists" do
          # Delete all route summaries
          RailsPulse::Summary.where(summarizable_type: "RailsPulse::Route").delete_all

          card = DatabaseLoad.new.to_metric_card

          assert_equal "—", card[:summary]
          assert_equal "—", card[:trend_amount]
        end

        test "shows 0% when no query data exists" do
          # Delete all summaries and create fresh route data
          RailsPulse::Summary.delete_all

          route = rails_pulse_routes(:api_users)
          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 5.days.ago.beginning_of_day,
            period_end: 5.days.ago.end_of_day,
            count: 100,
            total_duration: 10000.0
          )

          # No query summaries created
          card = DatabaseLoad.new.to_metric_card

          assert_equal "0.0%", card[:summary]
        end

        # Color Coding Tests

        test "sparkline bars are colored green when DB load is under 25%" do
          RailsPulse::Summary.delete_all

          route = rails_pulse_routes(:api_users)
          query = rails_pulse_queries(:complex_query)

          # Day 1: 20% DB load (green)
          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 100,
            total_duration: 10000.0
          )
          RailsPulse::Summary.create!(
            summarizable: query,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 500,
            total_duration: 2000.0  # 20%
          )

          card = DatabaseLoad.new.to_metric_card
          chart_data = card[:chart_data]

          # Find the bar for that day
          day_label = 3.days.ago.beginning_of_day.to_date.strftime("%b %-d")
          day_data = chart_data[day_label]

          assert_in_delta(20.0, day_data[:value])
          assert_includes day_data[:itemStyle][:color], "34, 197, 94"  # green
        end

        test "sparkline bars are colored yellow when DB load is 25-40%" do
          RailsPulse::Summary.delete_all

          route = rails_pulse_routes(:api_users)
          query = rails_pulse_queries(:complex_query)

          # Day 1: 30% DB load (yellow)
          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 100,
            total_duration: 10000.0
          )
          RailsPulse::Summary.create!(
            summarizable: query,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 500,
            total_duration: 3000.0  # 30%
          )

          card = DatabaseLoad.new.to_metric_card
          chart_data = card[:chart_data]

          day_label = 3.days.ago.beginning_of_day.to_date.strftime("%b %-d")
          day_data = chart_data[day_label]

          assert_in_delta(30.0, day_data[:value])
          assert_includes day_data[:itemStyle][:color], "234, 179, 8"  # yellow
        end

        test "sparkline bars are colored red when DB load is over 40%" do
          RailsPulse::Summary.delete_all

          route = rails_pulse_routes(:api_users)
          query = rails_pulse_queries(:complex_query)

          # Day 1: 50% DB load (red)
          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 100,
            total_duration: 10000.0
          )
          RailsPulse::Summary.create!(
            summarizable: query,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 500,
            total_duration: 5000.0  # 50%
          )

          card = DatabaseLoad.new.to_metric_card
          chart_data = card[:chart_data]

          day_label = 3.days.ago.beginning_of_day.to_date.strftime("%b %-d")
          day_data = chart_data[day_label]

          assert_in_delta(50.0, day_data[:value])
          assert_includes day_data[:itemStyle][:color], "239, 68, 68"  # red
        end

        # Trend Tests

        test "shows trending-up when DB load increased" do
          RailsPulse::Summary.delete_all

          route = rails_pulse_routes(:api_users)
          query = rails_pulse_queries(:complex_query)

          # Previous week: 20% DB load
          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 10.days.ago.beginning_of_day,
            period_end: 10.days.ago.end_of_day,
            count: 100,
            total_duration: 10000.0
          )
          RailsPulse::Summary.create!(
            summarizable: query,
            period_type: "day",
            period_start: 10.days.ago.beginning_of_day,
            period_end: 10.days.ago.end_of_day,
            count: 500,
            total_duration: 2000.0
          )

          # Current week: 40% DB load
          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 100,
            total_duration: 10000.0
          )
          RailsPulse::Summary.create!(
            summarizable: query,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 500,
            total_duration: 4000.0
          )

          card = DatabaseLoad.new.to_metric_card

          assert_equal "trending-up", card[:trend_icon]
        end

        test "shows trending-down when DB load decreased" do
          RailsPulse::Summary.delete_all

          route = rails_pulse_routes(:api_users)
          query = rails_pulse_queries(:complex_query)

          # Previous week: 40% DB load
          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 10.days.ago.beginning_of_day,
            period_end: 10.days.ago.end_of_day,
            count: 100,
            total_duration: 10000.0
          )
          RailsPulse::Summary.create!(
            summarizable: query,
            period_type: "day",
            period_start: 10.days.ago.beginning_of_day,
            period_end: 10.days.ago.end_of_day,
            count: 500,
            total_duration: 4000.0
          )

          # Current week: 20% DB load
          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 100,
            total_duration: 10000.0
          )
          RailsPulse::Summary.create!(
            summarizable: query,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 500,
            total_duration: 2000.0
          )

          card = DatabaseLoad.new.to_metric_card

          assert_equal "trending-down", card[:trend_icon]
        end

        test "shows move-right when change is less than 0.1%" do
          RailsPulse::Summary.delete_all

          route = rails_pulse_routes(:api_users)
          query = rails_pulse_queries(:complex_query)

          # Both weeks: 30% DB load
          [ 10.days.ago, 3.days.ago ].each do |date|
            RailsPulse::Summary.create!(
              summarizable: route,
              period_type: "day",
              period_start: date.beginning_of_day,
              period_end: date.end_of_day,
              count: 100,
              total_duration: 10000.0
            )
            RailsPulse::Summary.create!(
              summarizable: query,
              period_type: "day",
              period_start: date.beginning_of_day,
              period_end: date.end_of_day,
              count: 500,
              total_duration: 3000.0
            )
          end

          card = DatabaseLoad.new.to_metric_card

          assert_equal "move-right", card[:trend_icon]
        end

        # Sparkline Tests

        test "chart_data covers the default 7-day period" do
          # period: 7 (default) → 7 days ago through today = 8 entries
          card = DatabaseLoad.new.to_metric_card

          assert_equal 8, card[:chart_data].size
        end

        test "chart_data has itemStyle color for each day" do
          card = DatabaseLoad.new.to_metric_card

          card[:chart_data].each_value do |entry|
            assert_includes entry, :value
            assert_includes entry, :itemStyle
            assert_includes entry[:itemStyle], :color
          end
        end

        # Edge Cases

        test "handles days with zero request time" do
          RailsPulse::Summary.delete_all

          route = rails_pulse_routes(:api_users)
          query = rails_pulse_queries(:complex_query)

          # Day with 0 request time
          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 0,
            total_duration: 0.0
          )
          RailsPulse::Summary.create!(
            summarizable: query,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 100,
            total_duration: 1000.0
          )

          card = DatabaseLoad.new.to_metric_card
          chart_data = card[:chart_data]

          day_label = 3.days.ago.beginning_of_day.to_date.strftime("%b %-d")
          day_data = chart_data[day_label]

          # Should be 0% when request time is 0
          assert_in_delta(0.0, day_data[:value])
        end

        test "handles nil total_duration values" do
          RailsPulse::Summary.delete_all

          route = rails_pulse_routes(:api_users)

          RailsPulse::Summary.create!(
            summarizable: route,
            period_type: "day",
            period_start: 3.days.ago.beginning_of_day,
            period_end: 3.days.ago.end_of_day,
            count: 100,
            total_duration: nil  # nil value
          )

          assert_nothing_raised do
            DatabaseLoad.new.to_metric_card
          end
        end
      end
    end
  end
end
