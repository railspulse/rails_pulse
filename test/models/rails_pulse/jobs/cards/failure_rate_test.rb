require "test_helper"

module RailsPulse
  module Jobs
    module Cards
      class FailureRateTest < ActiveSupport::TestCase
        fixtures :rails_pulse_jobs

        def setup
          ENV["TEST_TYPE"] = "functional"
          super
          @job = rails_pulse_jobs(:report_job)

          # Clean up any existing summaries
          RailsPulse::Summary.delete_all

          # Freeze time for consistent testing
          @now = Time.current
          travel_to @now
        end

        def teardown
          travel_back
          super
        end

        # Structure Tests

        test "card returns hash with required keys" do
          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "jobs_failure_rate", result[:id]
          assert_equal "jobs", result[:context]
          assert_equal "Failure Rate", result[:title]
          assert_includes result.keys, :summary
          assert_includes result.keys, :chart_data
          assert_includes result.keys, :trend_icon
          assert_includes result.keys, :trend_amount
          assert_includes result.keys, :trend_text
        end

        # Calculation Tests - Specific Job

        test "card calculates failure rate for specific job" do
          # Create summaries for the report_job
          # Current window: 10 runs, 2 errors = 20% failure rate
          create_job_summary(
            job: @job,
            days_ago: 3,
            count: 10,
            error_count: 2
          )

          # Previous window: 10 runs, 1 error = 10% failure rate
          create_job_summary(
            job: @job,
            days_ago: 10,
            count: 10,
            error_count: 1
          )

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          # Total failure rate: 3 errors / 20 runs = 15%
          assert_equal "15.0%", result[:summary]

          # Trend: current 20% vs previous 10% = +100% (worse)
          assert_equal "trending-up", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        test "card calculates failure rate for all jobs when job is nil" do
          job1 = rails_pulse_jobs(:report_job)
          job2 = rails_pulse_jobs(:mailer_job)

          # Current window data
          create_job_summary(job: job1, days_ago: 3, count: 10, error_count: 2)
          create_job_summary(job: job2, days_ago: 3, count: 10, error_count: 3)

          # Previous window data
          create_job_summary(job: job1, days_ago: 10, count: 10, error_count: 1)
          create_job_summary(job: job2, days_ago: 10, count: 10, error_count: 1)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: nil)
          result = card.to_metric_card

          # Total failure rate: 7 errors / 40 runs = 17.5%
          assert_equal "17.5%", result[:summary]
        end

        test "card only includes summaries for specified job" do
          other_job = rails_pulse_jobs(:mailer_job)

          # Create summaries for both jobs
          create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 1)
          create_job_summary(job: other_job, days_ago: 3, count: 10, error_count: 5)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          # Should only include report_job's 10% failure rate, not mailer_job's 50%
          assert_equal "10.0%", result[:summary]
        end

        # Trend Tests

        test "card shows trending up when current failure rate is higher" do
          create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 5)
          create_job_summary(job: @job, days_ago: 10, count: 10, error_count: 1)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          # Current 50% vs previous 10% = +400% increase (worse)
          assert_equal "trending-up", result[:trend_icon]
          assert_equal "400.0%", result[:trend_amount]
        end

        test "card shows trending down when current failure rate is lower" do
          create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 1)
          create_job_summary(job: @job, days_ago: 10, count: 10, error_count: 5)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          # Current 10% vs previous 50% = -80% decrease (better)
          assert_equal "trending-down", result[:trend_icon]
          assert_equal "80.0%", result[:trend_amount]
        end

        test "card shows move right when trend is minimal" do
          create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 1)
          create_job_summary(job: @job, days_ago: 10, count: 10, error_count: 1)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        # Sparkline Tests

        test "card generates sparkline data for date range" do
          create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 2)
          create_job_summary(job: @job, days_ago: 5, count: 10, error_count: 3)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          assert_kind_of Hash, result[:chart_data]
          # Should have 14 days of data (RANGE_DAYS = 14)
          assert_equal 15, result[:chart_data].size

          # Each entry should have a label and value
          result[:chart_data].each do |label, data|
            assert_kind_of String, label
            assert_kind_of Hash, data
            assert_includes data.keys, :value
          end
        end

        test "card sparkline includes zero values for days with no data" do
          create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 2)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          # Most days should have 0.0 value
          zero_value_count = result[:chart_data].values.count { |v| v[:value] == 0.0 }

          assert_operator zero_value_count, :>, 10
        end

        test "card sparkline calculates failure rate percentages correctly" do
          create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 5)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          # Find the day with data
          day_with_data = result[:chart_data].values.find { |v| v[:value] > 0 }

          # Should be 50% (5 errors / 10 runs)
          assert_in_delta(50.0, day_with_data[:value])
        end

        # Edge Cases

        test "card handles job with no summaries" do
          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          assert_equal "0.0%", result[:summary]
          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        test "card handles job with no errors" do
          create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 0)
          create_job_summary(job: @job, days_ago: 10, count: 10, error_count: 0)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          assert_equal "0.0%", result[:summary]
          assert_equal "move-right", result[:trend_icon]
        end

        test "card handles 100% failure rate" do
          create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 10)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          assert_equal "100.0%", result[:summary]
        end

        test "card handles only current window data" do
          create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 2)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          assert_equal "20.0%", result[:summary]
          # No previous data means 0% trend
          assert_equal "move-right", result[:trend_icon]
        end

        test "card handles only previous window data" do
          create_job_summary(job: @job, days_ago: 10, count: 10, error_count: 3)

          card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
          result = card.to_metric_card

          assert_equal "30.0%", result[:summary]
          # Current is 0%, previous is 30%, so trending down 100%
          assert_equal "trending-down", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        private

        def create_job_summary(job:, days_ago:, count:, error_count:)
          period_start = days_ago.days.ago.beginning_of_day

          RailsPulse::Summary.create!(
            summarizable_type: "RailsPulse::Job",
            summarizable_id: job.id,
            period_start: period_start,
            period_end: period_start.end_of_day,
            period_type: "day",
            count: count,
            error_count: error_count,
            avg_duration: 0.0  # Not used for failure rate, but required by schema
          )
        end
      end
    end
  end
end
