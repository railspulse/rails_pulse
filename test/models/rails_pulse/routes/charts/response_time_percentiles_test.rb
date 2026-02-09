require "test_helper"

module RailsPulse
  module Routes
    module Charts
      class ResponseTimePercentilesTest < ActiveSupport::TestCase
        def setup
          @route = rails_pulse_routes(:api_test)
          @start_time = 1.day.ago.beginning_of_day
          @end_time = Time.current.end_of_day
          @ransack_query = RailsPulse::Summary.ransack
        end

        test "initializes with required parameters" do
          chart = ResponseTimePercentiles.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          assert_kind_of ResponseTimePercentiles, chart
        end

        test "returns chart data with labels and series" do
          chart = ResponseTimePercentiles.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          data = chart.to_chart_data

          assert data.key?(:labels)
          assert data.key?(:series)
          assert_kind_of Array, data[:labels]
          assert_kind_of Array, data[:series]
        end

        test "includes P95 and P99 series" do
          chart = ResponseTimePercentiles.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          data = chart.to_chart_data
          series_names = data[:series].map { |s| s[:name] }

          assert_includes series_names, "P95"
          assert_includes series_names, "P99"
        end

        test "P95 series has correct configuration" do
          chart = ResponseTimePercentiles.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          data = chart.to_chart_data
          p95_series = data[:series].find { |s| s[:name] == "P95" }

          assert_equal "line", p95_series[:type]
          assert_equal "#10b981", p95_series[:color]
          assert_kind_of Array, p95_series[:data]
        end

        test "P99 series has correct configuration" do
          chart = ResponseTimePercentiles.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          data = chart.to_chart_data
          p99_series = data[:series].find { |s| s[:name] == "P99" }

          assert_equal "line", p99_series[:type]
          assert_equal "#3b82f6", p99_series[:color]
          assert_kind_of Array, p99_series[:data]
        end

        test "filters by route when provided" do
          chart = ResponseTimePercentiles.new(
            ransack_query: @ransack_query,
            period_type: :day,
            route: @route,
            start_time: @start_time,
            end_time: @end_time
          )

          # Should not raise error
          data = chart.to_chart_data

          assert data.key?(:labels)
          assert data.key?(:series)
        end

        test "handles empty data gracefully" do
          # Create a ransack query that returns no results
          empty_query = RailsPulse::Summary.ransack(period_start_lt: 1.year.ago)

          chart = ResponseTimePercentiles.new(
            ransack_query: empty_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          data = chart.to_chart_data

          assert data.key?(:labels)
          assert data.key?(:series)
          # Should still have P95 and P99 series with zero values
          series_names = data[:series].map { |s| s[:name] }

          assert_includes series_names, "P95"
          assert_includes series_names, "P99"
        end

        test "includes SLO series when configured" do
          # Skip if no SLO configured
          skip unless RailsPulse.configuration.service_level_objective

          chart = ResponseTimePercentiles.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          data = chart.to_chart_data
          series_names = data[:series].map { |s| s[:name] }

          assert series_names.any? { |name| name.include?("Service Level Objective") }
        end
      end
    end
  end
end
