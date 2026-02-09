require "test_helper"

module RailsPulse
  module Queries
    module Cards
      class QueriesOverThresholdTest < ActiveSupport::TestCase
        fixtures :rails_pulse_queries, :rails_pulse_summaries

        def setup
          ENV["TEST_TYPE"] = "functional"
          super
          @query = rails_pulse_queries(:simple_query)
          @query2 = rails_pulse_queries(:complex_query)
          @card = QueriesOverThreshold.new(query: @query)
          @index_card = QueriesOverThreshold.new(query: nil)
          @now = Time.current
        end

        test "returns nil when query_service_level_objective is not configured" do
          # Temporarily disable SLO
          original_config = RailsPulse.configuration.query_service_level_objective
          RailsPulse.configuration.query_service_level_objective = nil

          result = @card.to_metric_card

          assert_nil result

          RailsPulse.configuration.query_service_level_objective = original_config
        end

        test "returns metric card when query_service_level_objective is configured" do
          result = @card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "queries_over_threshold", result[:id]
          assert_equal "queries", result[:context]
          assert_equal "Queries Over Threshold", result[:title]
          assert result.key?(:summary)
          assert result.key?(:chart_data)
          assert result.key?(:trend_icon)
          assert result.key?(:trend_amount)
          assert result.key?(:trend_text)
        end

        test "calculates percentage over threshold from summary data" do
          # Create summary data for last 14 days
          threshold = RailsPulse.configuration.query_service_level_objective[:threshold]

          7.times do |i|
            period_start = (@now - i.days).beginning_of_day
            # Create summaries where half of queries are over threshold
            RailsPulse::Summary.create!(
              summarizable: @query,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 100,
              p95_duration: threshold * 1.5,  # Over threshold
              p99_duration: threshold * 2.0,
              avg_duration: threshold * 0.8,
              p50_duration: threshold * 0.5
            )
          end

          result = @card.to_metric_card

          # Summary should show a percentage
          assert_predicate result[:summary], :present?
          assert_match(/\d+\.?\d*%/, result[:summary])
        end

        test "compares current week vs previous week for trend" do
          threshold = RailsPulse.configuration.query_service_level_objective[:threshold]

          # Previous week: 50% over threshold (p50 = threshold)
          7.times do |i|
            period_start = (@now - (i + 7).days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @query,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 100,
              p50_duration: threshold,
              p95_duration: threshold * 1.5,
              p99_duration: threshold * 2.0,
              avg_duration: threshold * 0.8
            )
          end

          # Current week: Only 25% over threshold (p50 below threshold)
          7.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @query,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 100,
              p50_duration: threshold * 0.8,
              p95_duration: threshold * 1.1,
              p99_duration: threshold * 1.3,
              avg_duration: threshold * 0.6
            )
          end

          result = @card.to_metric_card

          # Should show improvement (downward trend)
          assert_equal "trending-down", result[:trend_icon]
          assert_predicate result[:trend_amount], :present?
        end

        test "generates sparkline data for last 14 days" do
          threshold = RailsPulse.configuration.query_service_level_objective[:threshold]

          # Create 14 days of data
          14.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @query,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 100,
              p95_duration: threshold * (1.0 + (i * 0.05)),
              p99_duration: threshold * (1.2 + (i * 0.05)),
              p50_duration: threshold * 0.8,
              avg_duration: threshold * 0.7
            )
          end

          result = @card.to_metric_card

          assert_kind_of Hash, result[:chart_data]
          # 14 days from 2 weeks ago to today
          assert_operator result[:chart_data].keys.size, :>=, 14
          assert result[:chart_data].values.all? { |v| v.key?(:value) }
        end

        test "handles empty data gracefully" do
          # Clear all summaries
          RailsPulse::Summary.where(summarizable: @query, summarizable_type: "RailsPulse::Query").delete_all

          result = @card.to_metric_card

          assert_equal "0%", result[:summary]
          assert_equal "move-right", result[:trend_icon]
          assert_equal "0%", result[:trend_amount]
        end

        test "calculates for all queries when query is nil (index page)" do
          threshold = RailsPulse.configuration.query_service_level_objective[:threshold]

          # Clear existing summaries to avoid unique index conflicts
          RailsPulse::Summary.where(summarizable: [ @query, @query2 ], summarizable_type: "RailsPulse::Query").delete_all

          # Create summaries for multiple queries
          7.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @query,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 50,
              p95_duration: threshold * 1.5,
              p99_duration: threshold * 2.0,
              avg_duration: threshold * 0.8,
              p50_duration: threshold * 0.6
            )
            RailsPulse::Summary.create!(
              summarizable: @query2,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 50,
              p95_duration: threshold * 1.2,
              p99_duration: threshold * 1.5,
              avg_duration: threshold * 0.7,
              p50_duration: threshold * 0.5
            )
          end

          result = @index_card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "queries_over_threshold", result[:id]
          assert_predicate result[:summary], :present?
        end
      end
    end
  end
end
