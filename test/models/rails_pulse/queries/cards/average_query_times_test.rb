require "test_helper"

module RailsPulse
  module Queries
    module Cards
      class AverageQueryTimesTest < ActiveSupport::TestCase
        fixtures :rails_pulse_queries, :rails_pulse_summaries

        def setup
          ENV["TEST_TYPE"] = "functional"
          super

          @now = Time.current
          travel_to @now
        end

        def teardown
          travel_back
          super
        end

        # Structure Tests

        test "to_metric_card returns hash with required keys" do
          card = AverageQueryTimes.new

          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "average_query_times", result[:id]
          assert_equal "queries", result[:context]
          assert_equal "Average Query Time", result[:title]
          assert_includes result, :summary
          assert_includes result, :chart_data
          assert_includes result, :trend_icon
          assert_includes result, :trend_amount
          assert_includes result, :trend_text
        end

        test "to_metric_card summary is formatted as duration" do
          card = AverageQueryTimes.new

          result = card.to_metric_card

          assert_match(/\d+ ms/, result[:summary])
        end

        test "to_metric_card chart_data is a hash" do
          card = AverageQueryTimes.new

          result = card.to_metric_card

          assert_kind_of Hash, result[:chart_data]
        end

        # Calculation Tests

        test "calculates weighted average query duration" do
          # Create test data with known weighted average
          query = rails_pulse_queries(:simple_query)
          current_time = @now.beginning_of_day

          # Day 1: 10 queries at 100ms = 1000ms total
          RailsPulse::Summary.create!(
            summarizable: query,
            period_start: current_time - 3.days,
            period_end: (current_time - 3.days).end_of_day,
            period_type: "day",
            count: 10,
            avg_duration: 100.0
          )

          # Day 2: 20 queries at 50ms = 1000ms total
          RailsPulse::Summary.create!(
            summarizable: query,
            period_start: current_time - 4.days,
            period_end: (current_time - 4.days).end_of_day,
            period_type: "day",
            count: 20,
            avg_duration: 50.0
          )

          # Weighted average: (1000 + 1000) / (10 + 20) = 2000 / 30 = 66.67ms, rounds to 67ms
          card = AverageQueryTimes.new(query: query, period: 7, period_type: "day")

          result = card.to_metric_card

          assert_equal "67 ms", result[:summary]
        end

        test "handles queries with no executions" do
          query = rails_pulse_queries(:analyzed_query)
          # Use a query with no summary data for the requested time period
          card = AverageQueryTimes.new(query: query, period: 1, period_type: "day")

          result = card.to_metric_card

          assert_equal "0 ms", result[:summary]
          assert_equal "move-right", result[:trend_icon]
        end

        test "handles zero count gracefully" do
          card = AverageQueryTimes.new(period: 7, period_type: "day")

          result = card.to_metric_card

          assert_kind_of String, result[:summary]
          assert_includes result[:summary], "ms"
        end

        # Trend Tests

        test "shows trending-up when current period is slower" do
          query = rails_pulse_queries(:simple_query)
          current_time = @now.beginning_of_day

          # Current period (last 7 days): avg 150ms
          RailsPulse::Summary.create!(
            summarizable: query,
            period_start: current_time - 3.days,
            period_end: (current_time - 3.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 150.0
          )

          # Previous period (7-14 days ago): avg 100ms
          RailsPulse::Summary.create!(
            summarizable: query,
            period_start: current_time - 10.days,
            period_end: (current_time - 10.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 100.0
          )

          card = AverageQueryTimes.new(query: query, period: 7, period_type: "day")

          result = card.to_metric_card

          assert_equal "trending-up", result[:trend_icon]
          assert_equal "50.0%", result[:trend_amount]
        end

        test "shows trending-down when current period is faster" do
          query = rails_pulse_queries(:simple_query)
          current_time = @now.beginning_of_day

          # Current period: avg 50ms
          RailsPulse::Summary.create!(
            summarizable: query,
            period_start: current_time - 3.days,
            period_end: (current_time - 3.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 50.0
          )

          # Previous period: avg 100ms
          RailsPulse::Summary.create!(
            summarizable: query,
            period_start: current_time - 10.days,
            period_end: (current_time - 10.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 100.0
          )

          card = AverageQueryTimes.new(query: query, period: 7, period_type: "day")

          result = card.to_metric_card

          assert_equal "trending-down", result[:trend_icon]
          assert_equal "50.0%", result[:trend_amount]
        end

        test "shows move-right when change is minimal" do
          query = rails_pulse_queries(:simple_query)
          current_time = @now.beginning_of_day

          # Current period: avg 100.05ms
          RailsPulse::Summary.create!(
            summarizable: query,
            period_start: current_time - 3.days,
            period_end: (current_time - 3.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 100.05
          )

          # Previous period: avg 100ms (0.05% change)
          RailsPulse::Summary.create!(
            summarizable: query,
            period_start: current_time - 10.days,
            period_end: (current_time - 10.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 100.0
          )

          card = AverageQueryTimes.new(query: query, period: 7, period_type: "day")

          result = card.to_metric_card

          assert_equal "move-right", result[:trend_icon]
        end

        test "handles trend when previous period is zero" do
          query = rails_pulse_queries(:simple_query)
          current_time = @now.beginning_of_day

          # Current period: avg 100ms
          RailsPulse::Summary.create!(
            summarizable: query,
            period_start: current_time - 3.days,
            period_end: (current_time - 3.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 100.0
          )

          # No previous period data
          card = AverageQueryTimes.new(query: query, period: 7, period_type: "day")

          result = card.to_metric_card

          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        # Sparkline Tests - Day Period

        test "sparkline includes data for current period only" do
          query = rails_pulse_queries(:simple_query)
          current_time = @now.beginning_of_day

          # Create data for last 3 days (avoiding fixture times)
          3.times do |i|
            RailsPulse::Summary.create!(
              summarizable: query,
              period_start: current_time - (i + 2).days,
              period_end: (current_time - (i + 2).days).end_of_day,
              period_type: "day",
              count: 100,
              avg_duration: 50.0
            )
          end

          card = AverageQueryTimes.new(query: query, period: 7, period_type: "day")

          result = card.to_metric_card
          sparkline_data = result[:chart_data]

          # Should have 8 days (7 days ago through today)
          assert_equal 8, sparkline_data.size
        end

        test "sparkline fills missing days with zeros" do
          query = rails_pulse_queries(:simple_query)
          current_time = @now.beginning_of_day

          # Create data only for 2 days ago
          RailsPulse::Summary.create!(
            summarizable: query,
            period_start: current_time - 5.days,
            period_end: (current_time - 5.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 50.0
          )

          card = AverageQueryTimes.new(query: query, period: 7, period_type: "day")

          result = card.to_metric_card
          sparkline_data = result[:chart_data]

          # Should have 8 entries total (7 days + today)
          assert_equal 8, sparkline_data.size

          # Most should be zero
          zero_count = sparkline_data.count { |_k, v| v[:value] == 0 }

          assert_operator zero_count, :>=, 6
        end

        test "sparkline uses date labels for day period" do
          card = AverageQueryTimes.new(period: 7, period_type: "day")

          result = card.to_metric_card
          sparkline_data = result[:chart_data]

          # Keys should be date strings like "Jan 1"
          sparkline_data.keys.each do |key|
            assert_kind_of String, key
            assert_match(/[A-Z][a-z]{2} \d+/, key)
          end
        end

        # Sparkline Tests - Hour Period

        test "sparkline uses millisecond timestamps for hour period" do
          card = AverageQueryTimes.new(period: 1, period_type: "hour")

          result = card.to_metric_card
          sparkline_data = result[:chart_data]

          # Keys should be integers (timestamps in milliseconds)
          sparkline_data.keys.each do |key|
            assert_kind_of Integer, key
            assert_operator key, :>, 1000000000000  # Unix timestamp in milliseconds
          end
        end

        test "sparkline includes hourly data for hour period" do
          query = rails_pulse_queries(:simple_query)
          current_time = @now.beginning_of_hour

          # Create data for hours 5-7 (avoiding fixture times 1-3)
          3.times do |i|
            RailsPulse::Summary.create!(
              summarizable: query,
              period_start: current_time - (i + 5).hours,
              period_end: (current_time - (i + 5).hours).end_of_hour,
              period_type: "hour",
              count: 50,
              avg_duration: 25.0
            )
          end

          card = AverageQueryTimes.new(query: query, period: 1, period_type: "hour")

          result = card.to_metric_card
          sparkline_data = result[:chart_data]

          # Should have at least 20 hours of data
          assert_operator sparkline_data.size, :>=, 20
        end

        # Tag Filter Tests

        test "filters by disabled tags" do
          # Test that disabled_tags parameter is passed through correctly
          card = AverageQueryTimes.new(disabled_tags: [ "posts" ], period: 7, period_type: "day")

          result = card.to_metric_card

          # Should return valid structure (filtering is tested in Summary model)
          assert_kind_of Hash, result
          assert_includes result[:summary], "ms"
        end

        test "respects show_non_tagged parameter" do
          # Test that show_non_tagged parameter is passed through correctly
          card = AverageQueryTimes.new(show_non_tagged: false, period: 7, period_type: "day")

          result = card.to_metric_card

          # Should return valid structure (filtering is tested in Summary model)
          assert_kind_of Hash, result
          assert_includes result[:summary], "ms"
        end

        # Query-Specific Tests

        test "filters by specific query when provided" do
          query1 = rails_pulse_queries(:simple_query)
          query2 = rails_pulse_queries(:complex_query)
          current_time = @now.beginning_of_day

          RailsPulse::Summary.create!(
            summarizable: query1,
            period_start: current_time - 3.days,
            period_end: (current_time - 3.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 30.0
          )

          RailsPulse::Summary.create!(
            summarizable: query2,
            period_start: current_time - 3.days,
            period_end: (current_time - 3.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 90.0
          )

          # Filter to only query1
          card = AverageQueryTimes.new(query: query1, period: 7, period_type: "day")

          result = card.to_metric_card

          # Should only show query1's average
          assert_equal "30 ms", result[:summary]
        end

        test "includes all queries when no query specified" do
          query1 = rails_pulse_queries(:analyzed_query)
          query2 = rails_pulse_queries(:stale_analyzed_query)
          current_time = @now.beginning_of_day

          # Clear ALL query summaries for clean test
          RailsPulse::Summary.where(summarizable_type: "RailsPulse::Query", period_type: "day").delete_all

          RailsPulse::Summary.create!(
            summarizable: query1,
            period_start: current_time - 3.days,
            period_end: (current_time - 3.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 40.0
          )

          RailsPulse::Summary.create!(
            summarizable: query2,
            period_start: current_time - 3.days,
            period_end: (current_time - 3.days).end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 60.0
          )

          # No query filter - should include both
          card = AverageQueryTimes.new(period: 7, period_type: "day")

          result = card.to_metric_card

          # Weighted average: (40*100 + 60*100) / 200 = 50ms
          assert_equal "50 ms", result[:summary]
        end

        # Edge Cases

        test "handles very large period values" do
          card = AverageQueryTimes.new(period: 365, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_includes result, :summary
        end

        test "handles period of 0" do
          card = AverageQueryTimes.new(period: 0, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end

        test "handles nil disabled_tags" do
          card = AverageQueryTimes.new(disabled_tags: nil, period: 7, period_type: "day")

          assert_nothing_raised do
            card.to_metric_card
          end
        end

        test "handles empty disabled_tags array" do
          card = AverageQueryTimes.new(disabled_tags: [], period: 7, period_type: "day")

          result = card.to_metric_card

          assert_kind_of Hash, result
        end
      end
    end
  end
end
