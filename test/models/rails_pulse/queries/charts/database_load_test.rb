require "test_helper"

module RailsPulse
  module Queries
    module Charts
      class DatabaseLoadTest < ActiveSupport::TestCase
        fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_summaries

        def setup
          ENV["TEST_TYPE"] = "functional"
          super

          @start_time = 7.days.ago.beginning_of_day.to_i
          @end_time = Time.current.end_of_day.to_i
        end

        # Structure Tests

        test "to_chart_data returns hash or nil" do
          chart = DatabaseLoad.new(
            start_time: @start_time,
            end_time: @end_time,
            period_type: :day
          )

          result = chart.to_chart_data

          # Can be hash or nil if no data
          assert(result.nil? || result.is_a?(Hash))
        end

        test "returns nil when no query summaries exist" do
          # Use a future time range with no data
          future_start = 1.year.from_now.to_i
          future_end = 2.years.from_now.to_i

          chart = DatabaseLoad.new(
            start_time: future_start,
            end_time: future_end,
            period_type: :day
          )

          result = chart.to_chart_data

          assert_nil result
        end

        # Period Type Tests

        test "accepts day period_type" do
          chart = DatabaseLoad.new(
            start_time: @start_time,
            end_time: @end_time,
            period_type: :day
          )

          assert_nothing_raised do
            chart.to_chart_data
          end
        end

        test "accepts hour period_type" do
          start_time = 24.hours.ago.beginning_of_hour.to_i
          end_time = Time.current.end_of_hour.to_i

          chart = DatabaseLoad.new(
            start_time: start_time,
            end_time: end_time,
            period_type: :hour
          )

          assert_nothing_raised do
            chart.to_chart_data
          end
        end

        # Tag Filter Tests

        test "accepts disabled_tags parameter" do
          chart = DatabaseLoad.new(
            start_time: @start_time,
            end_time: @end_time,
            period_type: :day,
            disabled_tags: [ "slow" ]
          )

          assert_nothing_raised do
            chart.to_chart_data
          end
        end

        test "accepts show_non_tagged parameter" do
          chart = DatabaseLoad.new(
            start_time: @start_time,
            end_time: @end_time,
            period_type: :day,
            show_non_tagged: false
          )

          assert_nothing_raised do
            chart.to_chart_data
          end
        end

        test "accepts nil disabled_tags" do
          chart = DatabaseLoad.new(
            start_time: @start_time,
            end_time: @end_time,
            period_type: :day,
            disabled_tags: nil
          )

          assert_nothing_raised do
            chart.to_chart_data
          end
        end

        test "accepts empty disabled_tags array" do
          chart = DatabaseLoad.new(
            start_time: @start_time,
            end_time: @end_time,
            period_type: :day,
            disabled_tags: []
          )

          assert_nothing_raised do
            chart.to_chart_data
          end
        end

        # Edge Cases

        test "handles single day range" do
          start_time = Time.current.beginning_of_day.to_i
          end_time = Time.current.end_of_day.to_i

          chart = DatabaseLoad.new(
            start_time: start_time,
            end_time: end_time,
            period_type: :day
          )

          result = chart.to_chart_data

          # Can be nil or hash depending on data availability
          assert(result.nil? || result.is_a?(Hash))
        end

        test "handles large time range" do
          start_time = 30.days.ago.beginning_of_day.to_i
          end_time = Time.current.end_of_day.to_i

          chart = DatabaseLoad.new(
            start_time: start_time,
            end_time: end_time,
            period_type: :day
          )

          result = chart.to_chart_data

          assert(result.nil? || result.is_a?(Hash))
        end
      end
    end
  end
end
