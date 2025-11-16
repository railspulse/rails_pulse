require "test_helper"

module RailsPulse
  module Jobs
    module Cards
      class TotalRunsTest < ActiveSupport::TestCase
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

        test "card returns hash with required keys for specific job" do
          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "jobs_total_runs", result[:id]
          assert_equal "jobs", result[:context]
          assert_equal "Job Runs", result[:title]
          assert_includes result.keys, :summary
          assert_includes result.keys, :chart_data
          assert_includes result.keys, :trend_icon
          assert_includes result.keys, :trend_amount
          assert_includes result.keys, :trend_text
          assert_equal "Compared to previous week", result[:trend_text]
        end

        test "card returns hash with required keys for all jobs" do
          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: nil)
          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "jobs_total_runs", result[:id]
          assert_equal "jobs", result[:context]
          assert_equal "Job Runs", result[:title]
          assert_includes result.keys, :summary
          assert_includes result.keys, :chart_data
          assert_includes result.keys, :trend_icon
          assert_includes result.keys, :trend_amount
          assert_includes result.keys, :trend_text
        end

        # Calculation Tests - Specific Job

        test "card calculates total runs for specific job" do
          # Current window: 10 runs
          create_job_summary(job: @job, days_ago: 3, count: 10)

          # Previous window: 5 runs
          create_job_summary(job: @job, days_ago: 10, count: 5)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          # Total: 15 runs
          assert_equal "15 runs", result[:summary]

          # Trend: current 10 vs previous 5 = +100%
          assert_equal "trending-up", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        test "card only includes summaries for specified job" do
          other_job = rails_pulse_jobs(:mailer_job)

          # Create summaries for both jobs
          create_job_summary(job: @job, days_ago: 3, count: 10)
          create_job_summary(job: other_job, days_ago: 3, count: 100)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          # Should only include report_job's 10 runs, not mailer_job's 100 runs
          assert_equal "10 runs", result[:summary]
        end

        # Calculation Tests - All Jobs

        test "card calculates total runs for all jobs when job is nil" do
          job1 = rails_pulse_jobs(:report_job)
          job2 = rails_pulse_jobs(:mailer_job)

          # Current window data
          create_job_summary(job: job1, days_ago: 3, count: 10)
          create_job_summary(job: job2, days_ago: 3, count: 20)

          # Previous window data
          create_job_summary(job: job1, days_ago: 10, count: 5)
          create_job_summary(job: job2, days_ago: 10, count: 15)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: nil)
          result = card.to_metric_card

          # Total: 10 + 20 + 5 + 15 = 50 runs
          assert_equal "50 runs", result[:summary]

          # Trend: current 30 vs previous 20 = +50%
          assert_equal "trending-up", result[:trend_icon]
          assert_equal "50.0%", result[:trend_amount]
        end

        # Trend Tests

        test "card shows trending up when current runs increase" do
          create_job_summary(job: @job, days_ago: 3, count: 20)
          create_job_summary(job: @job, days_ago: 10, count: 10)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          assert_equal "trending-up", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        test "card shows trending down when current runs decrease" do
          create_job_summary(job: @job, days_ago: 3, count: 5)
          create_job_summary(job: @job, days_ago: 10, count: 10)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          assert_equal "trending-down", result[:trend_icon]
          assert_equal "50.0%", result[:trend_amount]
        end

        test "card shows move right when runs are stable" do
          create_job_summary(job: @job, days_ago: 3, count: 10)
          create_job_summary(job: @job, days_ago: 10, count: 10)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        # Sparkline Tests

        test "card generates sparkline data for date range" do
          create_job_summary(job: @job, days_ago: 3, count: 10)
          create_job_summary(job: @job, days_ago: 5, count: 5)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          assert_kind_of Hash, result[:chart_data]
          # Should have 15 days of data (14 days + today)
          assert_equal 15, result[:chart_data].size

          # Each entry should have a label and value
          result[:chart_data].each do |label, data|
            assert_kind_of String, label
            assert_kind_of Hash, data
            assert_includes data.keys, :value
          end
        end

        test "card sparkline includes zero values for days with no data" do
          create_job_summary(job: @job, days_ago: 3, count: 10)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          # Most days should have 0 value
          zero_value_count = result[:chart_data].values.count { |v| v[:value] == 0 }

          assert_operator zero_value_count, :>, 10
        end

        test "card sparkline shows run counts for days with data" do
          create_job_summary(job: @job, days_ago: 3, count: 25)
          create_job_summary(job: @job, days_ago: 5, count: 15)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          # Find days with data
          days_with_data = result[:chart_data].values.select { |v| v[:value] > 0 }

          # Should have 2 days with data
          assert_equal 2, days_with_data.length

          # Values should match the counts
          values = days_with_data.map { |d| d[:value] }.sort

          assert_equal [ 15, 25 ], values
        end

        # Edge Cases

        test "card handles job with no runs" do
          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          assert_equal "0 runs", result[:summary]
          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        test "card handles all jobs with no runs" do
          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: nil)
          result = card.to_metric_card

          assert_equal "0 runs", result[:summary]
          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        test "card handles only current window data" do
          create_job_summary(job: @job, days_ago: 3, count: 15)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          assert_equal "15 runs", result[:summary]
          # No previous data means 0, so move-right
          assert_equal "move-right", result[:trend_icon]
        end

        test "card handles only previous window data" do
          create_job_summary(job: @job, days_ago: 10, count: 20)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          assert_equal "20 runs", result[:summary]
          # Current is 0, previous is 20, so trending down 100%
          assert_equal "trending-down", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        test "card handles large run counts with number formatting" do
          create_job_summary(job: @job, days_ago: 3, count: 5000)
          create_job_summary(job: @job, days_ago: 5, count: 3500)

          card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
          result = card.to_metric_card

          # Should format with commas
          assert_equal "8,500 runs", result[:summary]
        end

        private

        def create_job_summary(job:, days_ago:, count:)
          period_start = days_ago.days.ago.beginning_of_day

          RailsPulse::Summary.create!(
            summarizable_type: "RailsPulse::Job",
            summarizable_id: job.id,
            period_start: period_start,
            period_end: period_start.end_of_day,
            period_type: "day",
            count: count,
            error_count: 0,  # Not used for total runs, but required by schema
            avg_duration: 0.0  # Not used for total runs, but required by schema
          )
        end
      end
    end
  end
end
