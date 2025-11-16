require "test_helper"

module RailsPulse
  module Jobs
    module Cards
      class TotalJobsTest < ActiveSupport::TestCase
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

          # Store initial job count for tests
          @initial_job_count = RailsPulse::Job.count
        end

        def teardown
          travel_back
          super
        end

        # Structure Tests - Specific Job

        test "card returns hash with required keys for specific job" do
          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: @job)
          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "jobs_total_jobs", result[:id]
          assert_equal "jobs", result[:context]
          assert_equal "Total Runs", result[:title]
          assert_includes result.keys, :summary
          assert_includes result.keys, :chart_data
          assert_includes result.keys, :trend_icon
          assert_includes result.keys, :trend_amount
          assert_includes result.keys, :trend_text
          assert_equal "Compared to previous week", result[:trend_text]
        end

        # Structure Tests - All Jobs

        test "card returns hash with required keys for all jobs" do
          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: nil)
          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "jobs_total_jobs", result[:id]
          assert_equal "jobs", result[:context]
          assert_equal "Total Jobs", result[:title]
          assert_includes result.keys, :summary
          assert_includes result.keys, :chart_data
          assert_includes result.keys, :trend_icon
          assert_includes result.keys, :trend_amount
          assert_includes result.keys, :trend_text
          assert_equal "New jobs vs previous week", result[:trend_text]
        end

        # Calculation Tests - Specific Job (Total Runs)

        test "card calculates total runs for specific job" do
          # Current window: 10 runs
          create_job_summary(job: @job, days_ago: 3, count: 10)

          # Previous window: 5 runs
          create_job_summary(job: @job, days_ago: 10, count: 5)

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: @job)
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

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: @job)
          result = card.to_metric_card

          # Should only include report_job's 10 runs, not other_job's 100 runs
          assert_equal "10 runs", result[:summary]
        end

        # Calculation Tests - All Jobs (Total Jobs Count)

        test "card calculates total jobs count" do
          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: nil)
          result = card.to_metric_card

          # Should count all fixture jobs
          assert_equal "#{@initial_job_count} jobs", result[:summary]
        end

        test "card tracks new jobs created in time windows" do
          # Current window: 2 new jobs
          travel_to 3.days.ago do
            RailsPulse::Job.create!(
              name: "CurrentJob1",
              queue_name: "default",
              runs_count: 0,
              failures_count: 0,
              retries_count: 0,
              avg_duration: 0.0
            )
          end

          travel_to 2.days.ago do
            RailsPulse::Job.create!(
              name: "CurrentJob2",
              queue_name: "default",
              runs_count: 0,
              failures_count: 0,
              retries_count: 0,
              avg_duration: 0.0
            )
          end

          # Previous window: 1 new job
          travel_to 10.days.ago do
            RailsPulse::Job.create!(
              name: "PreviousJob1",
              queue_name: "default",
              runs_count: 0,
              failures_count: 0,
              retries_count: 0,
              avg_duration: 0.0
            )
          end

          travel_to @now

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: nil)
          result = card.to_metric_card

          # Total: initial fixture jobs + 3 created above
          expected_count = @initial_job_count + 3

          assert_equal "#{expected_count} jobs", result[:summary]

          # Trend: 2 current vs 1 previous = +100%
          assert_equal "trending-up", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        # Trend Tests - Specific Job

        test "card shows trending up when current runs increase" do
          create_job_summary(job: @job, days_ago: 3, count: 20)
          create_job_summary(job: @job, days_ago: 10, count: 10)

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: @job)
          result = card.to_metric_card

          assert_equal "trending-up", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        test "card shows trending down when current runs decrease" do
          create_job_summary(job: @job, days_ago: 3, count: 5)
          create_job_summary(job: @job, days_ago: 10, count: 10)

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: @job)
          result = card.to_metric_card

          assert_equal "trending-down", result[:trend_icon]
          assert_equal "50.0%", result[:trend_amount]
        end

        test "card shows move right when runs are stable" do
          create_job_summary(job: @job, days_ago: 3, count: 10)
          create_job_summary(job: @job, days_ago: 10, count: 10)

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: @job)
          result = card.to_metric_card

          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        # Trend Tests - All Jobs

        test "card shows trending down when fewer new jobs are created" do
          # Previous window: 2 new jobs
          travel_to 12.days.ago do
            RailsPulse::Job.create!(name: "OldJob1", queue_name: "default", runs_count: 0, failures_count: 0, retries_count: 0, avg_duration: 0.0)
          end

          travel_to 10.days.ago do
            RailsPulse::Job.create!(name: "OldJob2", queue_name: "default", runs_count: 0, failures_count: 0, retries_count: 0, avg_duration: 0.0)
          end

          # Current window: 1 new job
          travel_to 3.days.ago do
            RailsPulse::Job.create!(name: "NewJob1", queue_name: "default", runs_count: 0, failures_count: 0, retries_count: 0, avg_duration: 0.0)
          end

          travel_to @now

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: nil)
          result = card.to_metric_card

          assert_equal "trending-down", result[:trend_icon]
          assert_equal "50.0%", result[:trend_amount]
        end

        # Sparkline Tests

        test "card generates sparkline data for specific job" do
          create_job_summary(job: @job, days_ago: 3, count: 10)
          create_job_summary(job: @job, days_ago: 5, count: 5)

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: @job)
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

        test "card generates sparkline data for all jobs" do
          travel_to 3.days.ago do
            RailsPulse::Job.create!(name: "RecentJob", queue_name: "default", runs_count: 0, failures_count: 0, retries_count: 0, avg_duration: 0.0)
          end

          travel_to @now

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: nil)
          result = card.to_metric_card

          assert_kind_of Hash, result[:chart_data]
          # Should have 15 days of data
          assert_equal 15, result[:chart_data].size
        end

        # Edge Cases - Specific Job

        test "card handles job with no runs" do
          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: @job)
          result = card.to_metric_card

          assert_equal "0 runs", result[:summary]
          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        test "card handles job with only current window data" do
          create_job_summary(job: @job, days_ago: 3, count: 15)

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: @job)
          result = card.to_metric_card

          assert_equal "15 runs", result[:summary]
          # No previous data means infinite growth, but previous is 0 so move-right
          assert_equal "move-right", result[:trend_icon]
        end

        test "card handles job with only previous window data" do
          create_job_summary(job: @job, days_ago: 10, count: 20)

          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: @job)
          result = card.to_metric_card

          assert_equal "20 runs", result[:summary]
          # Current is 0, previous is 20, so trending down 100%
          assert_equal "trending-down", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        # Edge Cases - All Jobs

        test "card handles no new jobs in either window" do
          # Fixture jobs were created before the test, so they're outside the 14-day range
          # No new jobs created in current or previous window
          card = RailsPulse::Jobs::Cards::TotalJobs.new(job: nil)
          result = card.to_metric_card

          # Should still count the fixture jobs
          assert_equal "#{@initial_job_count} jobs", result[:summary]

          # But trend should be flat (0 new jobs in both windows)
          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
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
            error_count: 0,  # Not used for total jobs, but required by schema
            avg_duration: 0.0  # Not used for total jobs, but required by schema
          )
        end
      end
    end
  end
end
