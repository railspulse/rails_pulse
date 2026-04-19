require "test_helper"

module RailsPulse
  module Jobs
    module Charts
      class ExecutionVolumeTest < ActiveSupport::TestCase
        fixtures :rails_pulse_jobs, :rails_pulse_summaries

        def setup
          ENV["TEST_TYPE"] = "functional"
          super

          RailsPulse::Summary.delete_all

          @job = rails_pulse_jobs(:report_job)
          @start_time = 7.days.ago.beginning_of_day
          @end_time = Time.current.end_of_day
          @ransack_query = RailsPulse::Summary.ransack
        end

        # Structure Tests

        test "to_chart_data returns hash with labels and series keys" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
          assert_includes result.keys, :labels
          assert_includes result.keys, :series
        end

        test "labels are timestamps in milliseconds" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Array, result[:labels]
          assert_operator result[:labels].length, :>, 0
          assert_operator result[:labels].first, :>, 1_000_000_000_000
        end

        test "series contains exactly one entry" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal 1, result[:series].length
        end

        test "series name is Executions" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal "Executions", result[:series].first[:name]
        end

        test "series type is bar" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal "bar", result[:series].first[:type]
        end

        test "series color is ChartColors::DEFAULT" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal RailsPulse::ChartColors::DEFAULT, result[:series].first[:color]
        end

        test "data array is same length as labels" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal result[:labels].length, result[:series].first[:data].length
        end

        # Calculation Tests

        test "sums execution counts by period" do
          # 100 + 50 = 150 executions on the same day
          create_summary(days_ago: 1, count: 100)
          create_summary(days_ago: 1, count: 50, job: rails_pulse_jobs(:mailer_job))

          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: 2.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data
          non_zero = result[:series].first[:data].select { |v| v > 0 }

          assert_operator non_zero.length, :>, 0
          assert_equal 150, non_zero.first
        end

        test "filters by job when subject provided" do
          other_job = rails_pulse_jobs(:mailer_job)
          create_summary(days_ago: 1, count: 100)
          create_summary(days_ago: 1, count: 999, job: other_job)

          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            subject: @job,
            start_time: 2.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data
          non_zero = result[:series].first[:data].select { |v| v > 0 }

          refute_includes non_zero, 999
          assert_equal 100, non_zero.first
        end

        test "daily step size is 86400 seconds" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: 3.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data

          if result[:labels].length > 1
            step_ms = result[:labels][1] - result[:labels][0]
            assert_equal 86400, step_ms / 1000
          end
        end

        test "hourly step size is 3600 seconds" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "hour",
            start_time: 3.hours.ago.beginning_of_hour,
            end_time: Time.current.end_of_hour
          )

          result = chart.to_chart_data

          if result[:labels].length > 1
            step_ms = result[:labels][1] - result[:labels][0]
            assert_equal 3600, step_ms / 1000
          end
        end

        # Edge Cases

        test "empty periods are filled with zeros" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: 100.days.ago.beginning_of_day,
            end_time: 99.days.ago.end_of_day
          )

          result = chart.to_chart_data

          assert_operator result[:labels].length, :>, 0
          result[:series].first[:data].each do |value|
            assert_equal 0, value
          end
        end

        test "handles empty result set" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
          assert_operator result[:labels].length, :>, 0
          result[:series].first[:data].each do |value|
            assert_equal 0, value
          end
        end

        test "handles large time range" do
          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: 90.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data

          assert_operator result[:labels].length, :>, 90
          assert_equal result[:labels].length, result[:series].first[:data].length
        end

        test "data values are integers" do
          create_summary(days_ago: 1, count: 42)

          chart = ExecutionVolume.new(
            ransack_query: @ransack_query,
            period_type: "day",
            subject: @job,
            start_time: 2.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data

          result[:series].first[:data].each do |value|
            assert_kind_of Integer, value
          end
        end

        private

        def create_summary(days_ago:, count:, job: @job)
          period_start = days_ago.days.ago.beginning_of_day
          RailsPulse::Summary.create!(
            summarizable_type: "RailsPulse::Job",
            summarizable_id: job.id,
            period_start: period_start,
            period_end: period_start.end_of_day,
            period_type: "day",
            count: count,
            avg_duration: 100.0
          )
        end
      end
    end
  end
end
