require "test_helper"

module RailsPulse
  module Jobs
    module Charts
      class FailureRateTest < ActiveSupport::TestCase
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
          chart = FailureRate.new(
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
          chart = FailureRate.new(
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
          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal 1, result[:series].length
        end

        test "series name is Failure Rate" do
          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal "Failure Rate", result[:series].first[:name]
        end

        test "series type is bar" do
          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal "bar", result[:series].first[:type]
        end

        test "series color is ChartColors::P95" do
          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal RailsPulse::ChartColors::P95, result[:series].first[:color]
        end

        test "data array is same length as labels" do
          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_equal result[:labels].length, result[:series].first[:data].length
        end

        # Calculation Tests

        test "calculates failure rate as percentage of errors to total" do
          # 10 errors out of 100 runs = 10.0%
          create_summary(days_ago: 1, count: 100, error_count: 10)

          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            subject: @job,
            start_time: 2.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data
          non_nil = result[:series].first[:data].compact

          assert_operator non_nil.length, :>, 0
          assert_in_delta 10.0, non_nil.first
        end

        test "calculates 100% failure rate when all runs fail" do
          create_summary(days_ago: 1, count: 50, error_count: 50)

          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            subject: @job,
            start_time: 2.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data
          non_nil = result[:series].first[:data].compact

          assert_in_delta 100.0, non_nil.first
        end

        test "calculates 0% failure rate when no errors" do
          create_summary(days_ago: 1, count: 80, error_count: 0)

          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            subject: @job,
            start_time: 2.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data
          non_nil = result[:series].first[:data].compact

          assert_in_delta 0.0, non_nil.first
        end

        test "sums counts and errors across multiple summaries in same period" do
          # 5/50 + 5/50 = 10/100 = 10.0%
          create_summary(days_ago: 1, count: 50, error_count: 5)
          create_summary(days_ago: 1, count: 50, error_count: 5, job: rails_pulse_jobs(:mailer_job))

          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: 2.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data
          non_nil = result[:series].first[:data].compact

          assert_in_delta 10.0, non_nil.first
        end

        test "filters by job when subject provided" do
          other_job = rails_pulse_jobs(:mailer_job)
          create_summary(days_ago: 1, count: 100, error_count: 10)
          create_summary(days_ago: 1, count: 100, error_count: 99, job: other_job)

          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            subject: @job,
            start_time: 2.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data
          non_nil = result[:series].first[:data].compact

          refute_includes non_nil, 99.0
          assert_in_delta 10.0, non_nil.first
        end

        test "daily step size is 86400 seconds" do
          chart = FailureRate.new(
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
          chart = FailureRate.new(
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

        test "periods with no data return nil" do
          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            subject: @job,
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert result[:series].first[:data].all?(&:nil?), "expected nil for all empty periods"
        end

        test "handles empty result set" do
          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: @start_time,
            end_time: @end_time
          )

          result = chart.to_chart_data

          assert_kind_of Hash, result
          assert_operator result[:labels].length, :>, 0
        end

        test "handles zero count summary without dividing by zero" do
          create_summary(days_ago: 1, count: 0, error_count: 0)

          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            subject: @job,
            start_time: 2.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          assert_nothing_raised { chart.to_chart_data }
        end

        test "handles large time range" do
          chart = FailureRate.new(
            ransack_query: @ransack_query,
            period_type: "day",
            start_time: 90.days.ago.beginning_of_day,
            end_time: Time.current.end_of_day
          )

          result = chart.to_chart_data

          assert_operator result[:labels].length, :>, 90
          assert_equal result[:labels].length, result[:series].first[:data].length
        end

        private

        def create_summary(days_ago:, count:, error_count: 0, job: @job)
          period_start = days_ago.days.ago.beginning_of_day
          RailsPulse::Summary.create!(
            summarizable_type: "RailsPulse::Job",
            summarizable_id: job.id,
            period_start: period_start,
            period_end: period_start.end_of_day,
            period_type: "day",
            count: count,
            error_count: error_count,
            avg_duration: 100.0
          )
        end
      end
    end
  end
end
