require "test_helper"

module RailsPulse
  module Jobs
    module Cards
      class P95DurationTest < ActiveSupport::TestCase
        fixtures :rails_pulse_jobs

        def setup
          ENV["TEST_TYPE"] = "functional"
          super
          @job = rails_pulse_jobs(:report_job)
          @card = P95Duration.new(job: @job)
          @index_card = P95Duration.new
          @now = Time.current

          # Clean up any existing summaries
          RailsPulse::Summary.delete_all
        end

        test "returns a metric card hash for a specific job" do
          card_data = @card.to_metric_card

          assert_kind_of Hash, card_data
          assert_equal "jobs_p95_duration", card_data[:id]
          assert_equal "jobs", card_data[:context]
          assert_equal "95th Percentile Duration", card_data[:title]
          assert card_data.key?(:summary)
          assert card_data.key?(:chart_data)
          assert card_data.key?(:trend_icon)
          assert card_data.key?(:trend_amount)
          assert card_data.key?(:trend_text)
        end

        test "returns a metric card hash for all jobs (index page)" do
          card_data = @index_card.to_metric_card

          assert_kind_of Hash, card_data
          assert_equal "jobs_p95_duration", card_data[:id]
          assert_equal "jobs", card_data[:context]
          assert_equal "95th Percentile Duration", card_data[:title]
        end

        test "calculates weighted P95 duration" do
          # Create summary data for the last 14 days
          14.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @job,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 10,
              p95_duration: 100 + (i * 10),  # Increasing duration
              p99_duration: 150 + (i * 10),
              avg_duration: 80 + (i * 10)
            )
          end

          card_data = @card.to_metric_card

          # The P95 should be around the weighted average
          assert_predicate card_data[:summary], :present?
          assert_match(/\d+ ms/, card_data[:summary])
        end

        test "generates sparkline data" do
          # Create summary data for the last 14 days
          14.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @job,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 10,
              p95_duration: 100 + (i * 10),
              p99_duration: 150 + (i * 10),
              avg_duration: 80 + (i * 10)
            )
          end

          card_data = @card.to_metric_card

          assert_kind_of Hash, card_data[:chart_data]
          # Range is 14 days from now - 14 days to now = 15 days inclusive
          assert_equal 15, card_data[:chart_data].keys.size
        end

        test "calculates trend" do
          # Create summary data for two windows
          # Previous week (8-14 days ago)
          7.times do |i|
            period_start = (@now - (8 + i).days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @job,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 10,
              p95_duration: 100,
              p99_duration: 150,
              avg_duration: 80
            )
          end

          # Current week (0-7 days ago) - higher values
          7.times do |i|
            period_start = (@now - i.days).beginning_of_day
            RailsPulse::Summary.create!(
              summarizable: @job,
              period_type: "day",
              period_start: period_start,
              period_end: period_start.end_of_day,
              count: 10,
              p95_duration: 200,
              p99_duration: 250,
              avg_duration: 180
            )
          end

          card_data = @card.to_metric_card

          assert_predicate card_data[:trend_icon], :present?
          assert_predicate card_data[:trend_amount], :present?
          assert_predicate card_data[:trend_text], :present?
          # Should show an upward trend since P95 increased
          assert_equal "trending-up", card_data[:trend_icon]
        end

        test "handles no data gracefully" do
          # Clear any existing summaries for this job
          RailsPulse::Summary.where(summarizable: @job, summarizable_type: "RailsPulse::Job").delete_all

          card_data = @card.to_metric_card

          assert_equal "0 ms", card_data[:summary]
          assert_equal "move-right", card_data[:trend_icon]
          assert_equal "0.0%", card_data[:trend_amount]
        end
      end
    end
  end
end
