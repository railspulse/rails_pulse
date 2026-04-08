require "test_helper"

module RailsPulse
  module Queries
    module Charts
      class ExecutionVolumeTest < ActiveSupport::TestCase
        fixtures :rails_pulse_queries, :rails_pulse_summaries

        def setup
          ENV["TEST_TYPE"] = "functional"
          super

          @start_time = 7.days.ago.beginning_of_day
          @end_time = Time.current.end_of_day
          @ransack_query = RailsPulse::Summary.ransack(period_start_gteq: @start_time)
        end

        # Structure Tests

        test "to_chart_data returns hash with required keys" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
          assert_includes result, :labels
          assert_includes result, :series
        end

        test "labels is an array" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Array, result[:labels]
        end

        test "series is an array" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Array, result[:series]
        end

        test "series contains hash with name, data, type, and color" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data
          series = result[:series].first

          assert_kind_of Hash, series
          assert_equal "Executions", series[:name]
          assert_kind_of Array, series[:data]
          assert_equal "bar", series[:type]
          assert_equal RailsPulse::ChartColors::DEFAULT, series[:color]
        end

        # Label Tests

        test "labels are timestamps in milliseconds" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          result[:labels].each do |label|
            assert_kind_of Integer, label
            assert_operator label, :>, 1000000000000  # Unix timestamp in milliseconds
          end
        end

        test "labels and data have same length" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal result[:labels].length, result[:series].first[:data].length
        end

        # Period Type Tests

        test "accepts day period_type" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
        end

        test "accepts hour period_type" do
          start_time = 24.hours.ago.beginning_of_hour
          end_time = Time.current.end_of_hour

          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :hour,
            start_time: start_time,
            end_time: end_time
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
        end

        # Subject Filtering Tests

        test "accepts subject parameter" do
          query = rails_pulse_queries(:simple_query)

          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            subject: query,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
        end

        test "accepts nil subject parameter" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            subject: nil,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
        end

        # Tag Filter Tests

        test "accepts disabled_tags parameter" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time,
            disabled_tags: [ "slow" ]
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
        end

        test "accepts show_non_tagged parameter" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time,
            show_non_tagged: false
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
        end

        test "accepts nil disabled_tags" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time,
            disabled_tags: nil
          )

          assert_nothing_raised do
            chart.to_chart_data
          end
        end

        # Data Padding Tests

        test "pads missing periods with zeros" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          # Should have entries for each day in the range
          expected_days = ((@end_time.to_date - @start_time.to_date).to_i + 1)

          assert_equal expected_days, result[:labels].length
        end

        # Edge Cases

        test "handles empty ransack query" do
          empty_query = RailsPulse::Summary.ransack

          chart = ExecutionVolume.new(
            ransack_query: empty_query,
            period_type: :day,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
        end

        test "handles single day range" do
          start_time = Time.current.beginning_of_day
          end_time = Time.current.end_of_day

          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: :day,
            start_time: start_time,
            end_time: end_time
          )

          result = chart.to_chart_data

          assert_equal 1, result[:labels].length
        end
      end
    end
  end
end
