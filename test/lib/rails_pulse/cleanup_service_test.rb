require "test_helper"

module RailsPulse
  class CleanupServiceTest < ActiveSupport::TestCase
    fixtures :rails_pulse_jobs, :rails_pulse_job_runs, :rails_pulse_routes,
             :rails_pulse_requests, :rails_pulse_operations, :rails_pulse_queries

    def setup
      super
      RailsPulse::Operation.delete_all
      RailsPulse::JobRun.delete_all
      RailsPulse::Request.delete_all
      RailsPulse::Route.delete_all
      RailsPulse::Query.delete_all
      RailsPulse::Job.delete_all

      @original_archiving = RailsPulse.configuration.archiving_enabled
      @original_retention = RailsPulse.configuration.full_retention_period
      @original_max_records = RailsPulse.configuration.max_table_records

      RailsPulse.configuration.archiving_enabled = true
    end

    def teardown
      RailsPulse.configuration.archiving_enabled = @original_archiving
      RailsPulse.configuration.full_retention_period = @original_retention
      RailsPulse.configuration.max_table_records = @original_max_records
      super
    end

    # Structure Tests

    test "perform returns a stats hash with time_based and count_based keys" do
      result = CleanupService.perform

      assert_kind_of Hash, result
      assert_includes result.keys, :time_based
      assert_includes result.keys, :count_based
      assert_includes result.keys, :total_deleted
    end

    test "perform returns zero stats when nothing to delete" do
      result = CleanupService.perform

      assert_equal 0, result[:total_deleted]
    end

    test "perform returns early without cleanup when archiving disabled" do
      RailsPulse.configuration.archiving_enabled = false

      result = CleanupService.perform

      assert_nil result
    end

    # Time-based Cleanup Tests

    test "time-based cleanup deletes operations older than retention period" do
      RailsPulse.configuration.full_retention_period = 30.days
      old_job = create_job("OldJob")
      old_run = create_job_run(old_job, occurred_at: 31.days.ago)
      create_operation(job_run: old_run, occurred_at: 31.days.ago)

      assert_difference -> { RailsPulse::Operation.count }, -1 do
        CleanupService.perform
      end
    end

    test "time-based cleanup keeps operations within retention period" do
      RailsPulse.configuration.full_retention_period = 30.days
      recent_job = create_job("RecentJob")
      recent_run = create_job_run(recent_job, occurred_at: 5.days.ago)
      create_operation(job_run: recent_run, occurred_at: 5.days.ago)

      assert_no_difference -> { RailsPulse::Operation.count } do
        CleanupService.perform
      end
    end

    test "time-based cleanup deletes old job runs" do
      RailsPulse.configuration.full_retention_period = 30.days
      old_job = create_job("OldJobRun")
      create_job_run(old_job, occurred_at: 40.days.ago)

      assert_difference -> { RailsPulse::JobRun.count }, -1 do
        CleanupService.perform
      end
    end

    test "time-based cleanup stats include deleted counts per table" do
      RailsPulse.configuration.full_retention_period = 30.days
      old_job = create_job("StatsJob")
      create_job_run(old_job, occurred_at: 60.days.ago)

      result = CleanupService.perform

      assert_operator result[:time_based][:job_runs], :>=, 1
      assert_operator result[:total_deleted], :>=, 1
    end

    # Count-based Cleanup Tests

    test "count-based cleanup deletes oldest jobs beyond max" do
      # Set limit to 2, create 3 jobs
      RailsPulse.configuration.max_table_records = {
        rails_pulse_operations: 10_000,
        rails_pulse_requests: 10_000,
        rails_pulse_job_runs: 10_000,
        rails_pulse_queries: 10_000,
        rails_pulse_routes: 10_000,
        rails_pulse_jobs: 2
      }
      RailsPulse.configuration.full_retention_period = nil

      # Disable time-based cleanup
      RailsPulse.configuration.instance_variable_set(:@full_retention_period, nil)

      3.times { |i| create_job("CountJob#{i}") }

      assert_difference -> { RailsPulse::Job.count }, -1 do
        CleanupService.perform
      end
    end

    test "count-based cleanup keeps jobs within max limit" do
      RailsPulse.configuration.max_table_records = {
        rails_pulse_operations: 10_000,
        rails_pulse_requests: 10_000,
        rails_pulse_job_runs: 10_000,
        rails_pulse_queries: 10_000,
        rails_pulse_routes: 10_000,
        rails_pulse_jobs: 10
      }
      RailsPulse.configuration.instance_variable_set(:@full_retention_period, nil)

      2.times { |i| create_job("SafeJob#{i}") }

      assert_no_difference -> { RailsPulse::Job.count } do
        CleanupService.perform
      end
    end

    # Edge Cases

    test "handles empty tables gracefully" do
      result = CleanupService.perform

      assert_equal 0, result[:total_deleted]
      assert_kind_of Hash, result[:time_based]
      assert_kind_of Hash, result[:count_based]
    end

    private

    def create_job(name)
      RailsPulse::Job.create!(name: name, queue_name: "default", runs_count: 0, failures_count: 0)
    end

    def create_job_run(job, occurred_at: Time.current)
      RailsPulse::JobRun.create!(
        job: job,
        run_id: SecureRandom.uuid,
        status: "success",
        adapter: "test",
        occurred_at: occurred_at
      )
    end

    def create_operation(job_run:, occurred_at: Time.current)
      RailsPulse::Operation.create!(
        job_run: job_run,
        operation_type: "sql",
        label: "SELECT 1",
        duration: 1.0,
        occurred_at: occurred_at,
        start_time: occurred_at.to_f
      )
    end
  end
end
