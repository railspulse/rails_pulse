require "test_helper"

module RailsPulse
  module Routes
    module Cards
      class RequestsOverThresholdTest < ActiveSupport::TestCase
        fixtures :rails_pulse_routes, :rails_pulse_summaries

        def setup
          ENV["TEST_TYPE"] = "functional"
          super
          @route = rails_pulse_routes(:api_users)
          @route2 = rails_pulse_routes(:api_posts)
          @card = RequestsOverThreshold.new(route: @route)
          @index_card = RequestsOverThreshold.new(route: nil)
          @now = Time.current
        end

        test "returns nil when service_level_objective is not configured" do
          original_config = RailsPulse.configuration.service_level_objective
          RailsPulse.configuration.service_level_objective = nil

          result = @card.to_metric_card

          assert_nil result
        ensure
          RailsPulse.configuration.service_level_objective = original_config
        end

        test "returns metric card when service_level_objective is configured" do
          result = @card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "requests_over_threshold", result[:id]
          assert_equal "routes", result[:context]
          assert_equal "Requests Over Threshold", result[:title]
          assert result.key?(:summary)
          assert result.key?(:chart_data)
          assert result.key?(:trend_icon)
          assert result.key?(:trend_amount)
          assert result.key?(:trend_text)
        end

        test "calculates percentage over threshold from summary data" do
          threshold = RailsPulse.configuration.service_level_objective[:threshold]

          7.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @route,
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

          result = @card.to_metric_card

          assert_predicate result[:summary], :present?
          assert_match(/\d+\.?\d*%/, result[:summary])
        end

        test "compares current week vs previous week for trend" do
          threshold = RailsPulse.configuration.service_level_objective[:threshold]

          # Previous week: 50% over threshold (p50 = threshold)
          7.times do |i|
            period_start = (@now - (i + 7).days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @route,
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

          # Current week: only ~5-25% over threshold (p50 below threshold)
          7.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @route,
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

          assert_equal "trending-down", result[:trend_icon]
          assert_predicate result[:trend_amount], :present?
        end

        test "generates sparkline data for last 14 days" do
          threshold = RailsPulse.configuration.service_level_objective[:threshold]

          14.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @route,
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
          assert_operator result[:chart_data].keys.size, :>=, 14
          assert result[:chart_data].values.all? { |v| v.key?(:value) }
        end

        test "handles empty data gracefully" do
          RailsPulse::Summary.where(summarizable: @route, summarizable_type: "RailsPulse::Route").delete_all

          result = @card.to_metric_card

          assert_equal "0%", result[:summary]
          assert_equal "move-right", result[:trend_icon]
          assert_equal "0%", result[:trend_amount]
        end

        test "calculates for all routes when route is nil (index page)" do
          threshold = RailsPulse.configuration.service_level_objective[:threshold]

          RailsPulse::Summary.where(summarizable: [ @route, @route2 ], summarizable_type: "RailsPulse::Route").delete_all

          7.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @route,
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
              summarizable: @route2,
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
          assert_equal "requests_over_threshold", result[:id]
          assert_predicate result[:summary], :present?
        end
      end
    end
  end
end
