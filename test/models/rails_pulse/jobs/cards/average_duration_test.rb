require "test_helper"

module RailsPulse
  module Jobs
    module Cards
      class AverageDurationTest < ActiveSupport::TestCase
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
          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "jobs_average_duration", result[:id]
          assert_equal "jobs", result[:context]
          assert_equal "Average Duration", result[:title]
          assert_includes result.keys, :summary
          assert_includes result.keys, :chart_data
          assert_includes result.keys, :trend_icon
          assert_includes result.keys, :trend_amount
          assert_includes result.keys, :trend_text
        end

        # Calculation Tests - Specific Job

        test "card calculates average duration for specific job" do
          # Create summaries for the report_job
          # Current window: last 7 days
          # Previous window: 8-14 days ago

          # Current window data (3 days ago: 100ms avg, 10 runs)
          create_job_summary(
            job: @job,
            days_ago: 3,
            count: 10,
            avg_duration: 100.0
          )

          # Previous window data (10 days ago: 200ms avg, 5 runs)
          create_job_summary(
            job: @job,
            days_ago: 10,
            count: 5,
            avg_duration: 200.0
          )

          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
          result = card.to_metric_card

          # Total average: (100*10 + 200*5) / (10+5) = 2000/15 = 133.3ms
          assert_equal "133 ms", result[:summary]

          # Trend: current 100ms vs previous 200ms = -50% (improvement)
          assert_equal "trending-down", result[:trend_icon]
          assert_equal "50.0%", result[:trend_amount]
        end

        test "card calculates average duration for all jobs when job is nil" do
          job1 = rails_pulse_jobs(:report_job)
          job2 = rails_pulse_jobs(:mailer_job)

          # Current window data
          create_job_summary(job: job1, days_ago: 3, count: 10, avg_duration: 100.0)
          create_job_summary(job: job2, days_ago: 3, count: 5, avg_duration: 200.0)

          # Previous window data
          create_job_summary(job: job1, days_ago: 10, count: 10, avg_duration: 150.0)
          create_job_summary(job: job2, days_ago: 10, count: 5, avg_duration: 300.0)

          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: nil)
          result = card.to_metric_card

          # Total average: (100*10 + 200*5 + 150*10 + 300*5) / (10+5+10+5) = 5000/30 = 166.7ms -> rounds to 167ms
          assert_equal "167 ms", result[:summary]
        end

        test "card only includes summaries for specified job" do
          other_job = rails_pulse_jobs(:mailer_job)

          # Create summaries for both jobs
          create_job_summary(job: @job, days_ago: 3, count: 10, avg_duration: 100.0)
          create_job_summary(job: other_job, days_ago: 3, count: 10, avg_duration: 500.0)

          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
          result = card.to_metric_card

          # Should only include report_job's 100ms, not mailer_job's 500ms
          assert_equal "100 ms", result[:summary]
        end

        # Trend Tests

        test "card shows trending up when current period is slower" do
          create_job_summary(job: @job, days_ago: 3, count: 10, avg_duration: 200.0)
          create_job_summary(job: @job, days_ago: 10, count: 10, avg_duration: 100.0)

          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
          result = card.to_metric_card

          assert_equal "trending-up", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        test "card shows trending down when current period is faster" do
          create_job_summary(job: @job, days_ago: 3, count: 10, avg_duration: 100.0)
          create_job_summary(job: @job, days_ago: 10, count: 10, avg_duration: 200.0)

          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
          result = card.to_metric_card

          assert_equal "trending-down", result[:trend_icon]
          assert_equal "50.0%", result[:trend_amount]
        end

        test "card shows move right when trend is minimal" do
          create_job_summary(job: @job, days_ago: 3, count: 10, avg_duration: 100.0)
          create_job_summary(job: @job, days_ago: 10, count: 10, avg_duration: 100.0)

          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
          result = card.to_metric_card

          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        # Sparkline Tests

        test "card generates sparkline data for date range" do
          create_job_summary(job: @job, days_ago: 3, count: 10, avg_duration: 100.0)
          create_job_summary(job: @job, days_ago: 5, count: 5, avg_duration: 150.0)

          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
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
          create_job_summary(job: @job, days_ago: 3, count: 10, avg_duration: 100.0)

          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
          result = card.to_metric_card

          # Most days should have 0.0 value
          zero_value_count = result[:chart_data].values.count { |v| v[:value] == 0.0 }

          assert_operator zero_value_count, :>, 10
        end

        # Edge Cases

        test "card handles job with no summaries" do
          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
          result = card.to_metric_card

          assert_equal "0 ms", result[:summary]
          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        test "card handles only current window data" do
          create_job_summary(job: @job, days_ago: 3, count: 10, avg_duration: 100.0)

          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
          result = card.to_metric_card

          assert_equal "100 ms", result[:summary]
          # No previous data means 0% trend
          assert_equal "move-right", result[:trend_icon]
        end

        test "card handles only previous window data" do
          create_job_summary(job: @job, days_ago: 10, count: 10, avg_duration: 200.0)

          card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job)
          result = card.to_metric_card

          assert_equal "200 ms", result[:summary]
          # Current is 0, previous is 200, so trending down 100%
          assert_equal "trending-down", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        private

        def create_job_summary(job:, days_ago:, count:, avg_duration:)
          period_start = days_ago.days.ago.beginning_of_day

          RailsPulse::Summary.create!(
            summarizable_type: "RailsPulse::Job",
            summarizable_id: job.id,
            period_start: period_start,
            period_end: period_start.end_of_day,
            period_type: "day",
            count: count,
            avg_duration: avg_duration
          )
        end
      end
    end
  end
end
