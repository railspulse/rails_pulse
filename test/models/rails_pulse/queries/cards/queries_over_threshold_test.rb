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

        test "returns empty array when query_service_level_objectives is not configured" do
          original_config = RailsPulse.configuration.query_service_level_objectives
          RailsPulse.configuration.query_service_level_objectives = []

          result = @card.to_metric_cards

          assert_empty result
        ensure
          RailsPulse.configuration.query_service_level_objectives = original_config
        end

        test "returns metric cards when query_service_level_objectives is configured" do
          result = @card.to_metric_cards

          assert_kind_of Array, result
          assert_not_empty result
          result.each do |card|
            assert_kind_of Hash, card
            assert_match(/queries_over_threshold_p\d+/, card[:id])
            assert_equal "queries", card[:context]
            assert_match(/P\d+ Queries Over Threshold/, card[:title])
            assert card.key?(:summary)
            assert card.key?(:chart_data)
            assert card.key?(:trend_icon)
            assert card.key?(:trend_amount)
            assert card.key?(:trend_text)
          end
        end

        test "returns one card per configured SLO" do
          original_config = RailsPulse.configuration.query_service_level_objectives
          RailsPulse.configuration.query_service_level_objectives = [
            { percentile: 95, threshold: 50 },
            { percentile: 99, threshold: 100 }
          ]

          result = @card.to_metric_cards

          assert_equal 2, result.length
          assert_equal "queries_over_threshold_p95", result[0][:id]
          assert_equal "P95 Queries Over Threshold", result[0][:title]
          assert_equal "queries_over_threshold_p99", result[1][:id]
          assert_equal "P99 Queries Over Threshold", result[1][:title]
        ensure
          RailsPulse.configuration.query_service_level_objectives = original_config
        end

        test "calculates percentage over threshold from summary data" do
          threshold = RailsPulse.configuration.query_service_level_objectives.first[:threshold]

          7.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @query,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 100,
              p95_duration: threshold * 1.5,
              p99_duration: threshold * 2.0,
              avg_duration: threshold * 0.8,
              p50_duration: threshold * 0.5
            )
          end

          result = @card.to_metric_cards

          assert_not_empty result
          result.each do |card|
            assert_predicate card[:summary], :present?
            assert_match(/\d+\.?\d*%/, card[:summary])
          end
        end

        test "compares current week vs previous week for trend" do
          original_config = RailsPulse.configuration.query_service_level_objectives
          RailsPulse.configuration.query_service_level_objectives = [ { percentile: 95, threshold: 100 } ]
          threshold = 100

          # Previous week: p95 above threshold — all traffic failing SLO
          7.times do |i|
            period_start = (@now - (i + 7).days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @query,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 100,
              p50_duration: threshold * 0.6,
              p95_duration: threshold * 1.5,
              p99_duration: threshold * 2.0,
              avg_duration: threshold * 0.8
            )
          end

          # Current week: p95 below threshold — no traffic failing SLO
          7.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @query,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 100,
              p50_duration: threshold * 0.4,
              p95_duration: threshold * 0.8,
              p99_duration: threshold * 0.9,
              avg_duration: threshold * 0.5
            )
          end

          result = @card.to_metric_cards

          assert_equal 1, result.length
          assert_equal "trending-down", result.first[:trend_icon]
          assert_predicate result.first[:trend_amount], :present?
        ensure
          RailsPulse.configuration.query_service_level_objectives = original_config
        end

        test "generates sparkline data for last 14 days" do
          threshold = RailsPulse.configuration.query_service_level_objectives.first[:threshold]

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

          result = @card.to_metric_cards

          assert_not_empty result
          result.each do |card|
            assert_kind_of Hash, card[:chart_data]
            assert_operator card[:chart_data].keys.size, :>=, 14
            assert card[:chart_data].values.all? { |v| v.key?(:value) }
          end
        end

        test "handles empty data gracefully" do
          RailsPulse::Summary.where(summarizable: @query, summarizable_type: "RailsPulse::Query").delete_all

          result = @card.to_metric_cards

          assert_not_empty result
          result.each do |card|
            assert_equal "—", card[:summary]
            assert_equal "move-right", card[:trend_icon]
            assert_equal "—", card[:trend_amount]
          end
        end

        test "calculates for all queries when query is nil (index page)" do
          threshold = RailsPulse.configuration.query_service_level_objectives.first[:threshold]

          RailsPulse::Summary.where(summarizable: [ @query, @query2 ], summarizable_type: "RailsPulse::Query").delete_all

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

          result = @index_card.to_metric_cards

          assert_kind_of Array, result
          assert_not_empty result
          result.each do |card|
            assert_match(/queries_over_threshold_p\d+/, card[:id])
            assert_predicate card[:summary], :present?
          end
        end

        # Division-by-zero guard tests

        test "handles p95_duration equal to p50_duration without error" do
          threshold = 30

          RailsPulse::Summary.create!(
            summarizable: @query,
            period_type: "day",
            period_start: @now.beginning_of_day,
            period_end: @now.end_of_day,
            count: 100,
            p50_duration: 40,
            p95_duration: 40,  # equal to p50 — division by zero guard
            p99_duration: 80,
            avg_duration: 35
          )

          original_config = RailsPulse.configuration.query_service_level_objectives
          RailsPulse.configuration.query_service_level_objectives = [ { percentile: 95, threshold: threshold } ]

          result = @card.to_metric_cards

          assert_not_empty result
          assert_match(/\d+\.?\d*%/, result.first[:summary])
        ensure
          RailsPulse.configuration.query_service_level_objectives = original_config
        end

        test "handles p99_duration equal to p95_duration without error" do
          threshold = 45

          RailsPulse::Summary.create!(
            summarizable: @query,
            period_type: "day",
            period_start: @now.beginning_of_day,
            period_end: @now.end_of_day,
            count: 100,
            p50_duration: 30,
            p95_duration: 50,
            p99_duration: 50,  # equal to p95 — division by zero guard
            avg_duration: 35
          )

          original_config = RailsPulse.configuration.query_service_level_objectives
          RailsPulse.configuration.query_service_level_objectives = [ { percentile: 99, threshold: threshold } ]

          result = @card.to_metric_cards

          assert_not_empty result
          assert_match(/\d+\.?\d*%/, result.first[:summary])
        ensure
          RailsPulse.configuration.query_service_level_objectives = original_config
        end

        test "handles max_duration equal to p99_duration without error" do
          threshold = 60

          RailsPulse::Summary.create!(
            summarizable: @query,
            period_type: "day",
            period_start: @now.beginning_of_day,
            period_end: @now.end_of_day,
            count: 100,
            p50_duration: 20,
            p95_duration: 40,
            p99_duration: 50,
            max_duration: 50,  # equal to p99 — no queries above threshold
            avg_duration: 30
          )

          original_config = RailsPulse.configuration.query_service_level_objectives
          RailsPulse.configuration.query_service_level_objectives = [ { percentile: 99, threshold: threshold } ]

          result = @card.to_metric_cards

          assert_not_empty result
          assert_equal "0.0%", result.first[:summary]
        ensure
          RailsPulse.configuration.query_service_level_objectives = original_config
        end

        test "returns zero (not negative) when max_duration is between p99 and threshold" do
          # Bug scenario: p99 < max_duration < threshold
          # Previously produced negative ratio and negative count
          threshold = 60

          RailsPulse::Summary.create!(
            summarizable: @query,
            period_type: "day",
            period_start: @now.beginning_of_day,
            period_end: @now.end_of_day,
            count: 100,
            p50_duration: 20,
            p95_duration: 40,
            p99_duration: 50,
            max_duration: 55,  # between p99 (50) and threshold (60)
            avg_duration: 30
          )

          original_config = RailsPulse.configuration.query_service_level_objectives
          RailsPulse.configuration.query_service_level_objectives = [ { percentile: 99, threshold: threshold } ]

          result = @card.to_metric_cards

          assert_not_empty result
          percentage = result.first[:summary].to_f

          assert_operator percentage, :>=, 0, "Percentage should not be negative"
          assert_equal "0.0%", result.first[:summary]
        ensure
          RailsPulse.configuration.query_service_level_objectives = original_config
        end

        test "handles all percentiles at zero without error" do
          threshold = 10

          RailsPulse::Summary.create!(
            summarizable: @query,
            period_type: "day",
            period_start: @now.beginning_of_day,
            period_end: @now.end_of_day,
            count: 100,
            p50_duration: 0,
            p95_duration: 0,
            p99_duration: 0,
            max_duration: 0,
            avg_duration: 0
          )

          original_config = RailsPulse.configuration.query_service_level_objectives
          RailsPulse.configuration.query_service_level_objectives = [ { percentile: 95, threshold: threshold } ]

          result = @card.to_metric_cards

          assert_not_empty result
          assert_match(/\d+\.?\d*%/, result.first[:summary])
        ensure
          RailsPulse.configuration.query_service_level_objectives = original_config
        end
      end
    end
  end
end
