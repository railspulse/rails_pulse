require "test_helper"

module RailsPulse
  class CleanupServiceTest < ActiveSupport::TestCase
    fixtures :rails_pulse_jobs, :rails_pulse_job_runs, :rails_pulse_routes,
             :rails_pulse_requests, :rails_pulse_operations, :rails_pulse_queries

    def setup
      super
      RailsPulse::Summary.delete_all
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

    # Summarization Guard Tests

    test "count-based request cleanup does nothing when no summaries exist" do
      RailsPulse.configuration.max_table_records = {
        rails_pulse_operations: 10_000,
        rails_pulse_requests: 2,
        rails_pulse_job_runs: 10_000,
        rails_pulse_queries: 10_000,
        rails_pulse_routes: 10_000,
        rails_pulse_jobs: 10_000
      }
      RailsPulse.configuration.instance_variable_set(:@full_retention_period, nil)

      route = RailsPulse::Route.create!(method: "GET", path: "/guard-test")
      3.times do
        RailsPulse::Request.create!(
          route: route, duration: 100.0, status: 200, is_error: false,
          request_uuid: SecureRandom.uuid, occurred_at: 3.hours.ago
        )
      end

      assert_no_difference -> { RailsPulse::Request.count } do
        CleanupService.perform
      end
    end

    test "count-based request cleanup deletes requests older than summarization cutoff" do
      RailsPulse.configuration.max_table_records = {
        rails_pulse_operations: 10_000,
        rails_pulse_requests: 2,
        rails_pulse_job_runs: 10_000,
        rails_pulse_queries: 10_000,
        rails_pulse_routes: 10_000,
        rails_pulse_jobs: 10_000
      }
      RailsPulse.configuration.instance_variable_set(:@full_retention_period, nil)

      # Summary covering 3 hours ago — anything before period_end is safe to delete
      period_end = 2.hours.ago
      create_overall_hourly_summary(period_end: period_end)

      route = RailsPulse::Route.create!(method: "GET", path: "/guard-test-2")
      3.times do
        RailsPulse::Request.create!(
          route: route, duration: 100.0, status: 200, is_error: false,
          request_uuid: SecureRandom.uuid, occurred_at: 3.hours.ago
        )
      end

      # 3 requests exist, max is 2 — 1 should be deleted since they're before cutoff
      assert_difference -> { RailsPulse::Request.count }, -1 do
        CleanupService.perform
      end
    end

    test "count-based request cleanup does not delete requests newer than summarization cutoff" do
      RailsPulse.configuration.max_table_records = {
        rails_pulse_operations: 10_000,
        rails_pulse_requests: 2,
        rails_pulse_job_runs: 10_000,
        rails_pulse_queries: 10_000,
        rails_pulse_routes: 10_000,
        rails_pulse_jobs: 10_000
      }
      RailsPulse.configuration.instance_variable_set(:@full_retention_period, nil)

      # Summary only covers up to 3 hours ago
      create_overall_hourly_summary(period_end: 3.hours.ago)

      route = RailsPulse::Route.create!(method: "GET", path: "/guard-test-3")
      3.times do
        # Requests are from 30 minutes ago — newer than the summarization cutoff
        RailsPulse::Request.create!(
          route: route, duration: 100.0, status: 200, is_error: false,
          request_uuid: SecureRandom.uuid, occurred_at: 30.minutes.ago
        )
      end

      assert_no_difference -> { RailsPulse::Request.count } do
        CleanupService.perform
      end
    end

    test "count-based operations cleanup does nothing when no summaries exist" do
      RailsPulse.configuration.max_table_records = {
        rails_pulse_operations: 2,
        rails_pulse_requests: 10_000,
        rails_pulse_job_runs: 10_000,
        rails_pulse_queries: 10_000,
        rails_pulse_routes: 10_000,
        rails_pulse_jobs: 10_000
      }
      RailsPulse.configuration.instance_variable_set(:@full_retention_period, nil)

      job = create_job("OpsGuardJob")
      run = create_job_run(job, occurred_at: 3.hours.ago)
      3.times { create_operation(job_run: run, occurred_at: 3.hours.ago) }

      assert_no_difference -> { RailsPulse::Operation.count } do
        CleanupService.perform
      end
    end

    # Race Condition Tests

    test "time-based route cleanup does not delete a route that has an associated request" do
      # The old implementation used a two-step pluck+delete, which had a race window:
      # a request created after the pluck but before the delete_all could cause an FK
      # violation (MySQL) or silent data loss (SQLite without FK enforcement).
      # The fix uses an atomic subquery so the existence check and delete happen together.
      RailsPulse.configuration.full_retention_period = 1.hour

      old_route = RailsPulse::Route.create!(method: "GET", path: "/api/stale", created_at: 2.hours.ago)
      RailsPulse::Request.create!(
        route: old_route,
        duration: 100.0, status: 200, is_error: false,
        request_uuid: SecureRandom.uuid,
        controller_action: "Api::StaleController#index",
        occurred_at: Time.current
      )

      begin
        CleanupService.perform
      rescue ActiveRecord::InvalidForeignKey
        flunk "FK constraint violated: route was deleted despite having an associated request"
      end

      assert RailsPulse::Route.exists?(old_route.id),
        "Route was deleted despite having an associated request"
    end

    test "count-based route cleanup does not delete a route that has an associated request" do
      # Same race condition as the time-based variant — fixed by using an atomic subquery.
      RailsPulse.configuration.max_table_records = {
        rails_pulse_operations: 10_000,
        rails_pulse_requests:   10_000,
        rails_pulse_job_runs:   10_000,
        rails_pulse_queries:    10_000,
        rails_pulse_routes:     1,
        rails_pulse_jobs:       10_000
      }
      RailsPulse.configuration.instance_variable_set(:@full_retention_period, nil)

      # Two routes so count (2) exceeds max (1) — oldest is a deletion candidate
      old_route = RailsPulse::Route.create!(method: "GET", path: "/api/old", created_at: 3.hours.ago)
      RailsPulse::Route.create!(method: "GET", path: "/api/new", created_at: 1.hour.ago)

      # old_route has a request — it must not be deleted even though it's the oldest
      RailsPulse::Request.create!(
        route: old_route,
        duration: 100.0, status: 200, is_error: false,
        request_uuid: SecureRandom.uuid,
        controller_action: "Api::OldController#index",
        occurred_at: Time.current
      )

      begin
        CleanupService.perform
      rescue ActiveRecord::InvalidForeignKey
        flunk "FK constraint violated: route was deleted despite having an associated request"
      end

      assert RailsPulse::Route.exists?(old_route.id),
        "Route was deleted despite having an associated request"
    end

    test "time-based query cleanup does not delete a query that has an associated operation" do
      # Operation's before_validation callback (associate_query) manages the query association
      # via find_or_create_by(hashed_sql), so we bootstrap the query through the callback.
      RailsPulse.configuration.full_retention_period = 1.hour

      job = create_job("QueryRaceJob")
      run = create_job_run(job, occurred_at: Time.current)
      op = RailsPulse::Operation.create!(
        job_run: run, operation_type: "sql", label: "SELECT * FROM users WHERE id = 1",
        duration: 1.0, occurred_at: Time.current, start_time: Time.current.to_f
      )
      old_query = op.query
      old_query.update_column(:created_at, 2.hours.ago)

      begin
        CleanupService.perform
      rescue ActiveRecord::InvalidForeignKey
        flunk "FK constraint violated: query was deleted despite having an associated operation"
      end

      assert RailsPulse::Query.exists?(old_query.id),
        "Query was deleted despite having an associated operation"
    end

    test "count-based query cleanup does not delete a query that has an associated operation" do
      RailsPulse.configuration.max_table_records = {
        rails_pulse_operations: 10_000,
        rails_pulse_requests:   10_000,
        rails_pulse_job_runs:   10_000,
        rails_pulse_queries:    1,
        rails_pulse_routes:     10_000,
        rails_pulse_jobs:       10_000
      }
      RailsPulse.configuration.instance_variable_set(:@full_retention_period, nil)

      # Create old_query via the callback
      job = create_job("QueryCountRaceJob")
      run = create_job_run(job, occurred_at: Time.current)
      op = RailsPulse::Operation.create!(
        job_run: run, operation_type: "sql", label: "SELECT * FROM orders WHERE id = 1",
        duration: 1.0, occurred_at: Time.current, start_time: Time.current.to_f
      )
      old_query = op.query
      old_query.update_column(:created_at, 3.hours.ago)

      # A second query so count (2) exceeds max (1) — old_query is the deletion candidate
      job2 = create_job("QueryCountRaceJob2")
      run2 = create_job_run(job2, occurred_at: Time.current)
      RailsPulse::Operation.create!(
        job_run: run2, operation_type: "sql", label: "SELECT * FROM products WHERE id = 1",
        duration: 1.0, occurred_at: Time.current, start_time: Time.current.to_f
      )

      begin
        CleanupService.perform
      rescue ActiveRecord::InvalidForeignKey
        flunk "FK constraint violated: query was deleted despite having an associated operation"
      end

      assert RailsPulse::Query.exists?(old_query.id),
        "Query was deleted despite having an associated operation"
    end

    test "time-based job cleanup does not delete a job that has an associated job run" do
      RailsPulse.configuration.full_retention_period = 1.hour

      old_job = create_job("StaleJob")
      old_job.update_column(:created_at, 2.hours.ago)
      create_job_run(old_job, occurred_at: Time.current)

      begin
        CleanupService.perform
      rescue ActiveRecord::InvalidForeignKey
        flunk "FK constraint violated: job was deleted despite having an associated job run"
      end

      assert RailsPulse::Job.exists?(old_job.id),
        "Job was deleted despite having an associated job run"
    end

    test "count-based job cleanup does not delete a job that has an associated job run" do
      RailsPulse.configuration.max_table_records = {
        rails_pulse_operations: 10_000,
        rails_pulse_requests:   10_000,
        rails_pulse_job_runs:   10_000,
        rails_pulse_queries:    10_000,
        rails_pulse_routes:     10_000,
        rails_pulse_jobs:       1
      }
      RailsPulse.configuration.instance_variable_set(:@full_retention_period, nil)

      old_job = create_job("OldCountJob")
      old_job.update_column(:created_at, 3.hours.ago)
      create_job_run(old_job, occurred_at: Time.current)

      # A second job so count (2) exceeds max (1) — old_job is the deletion candidate
      create_job("NewCountJob")

      begin
        CleanupService.perform
      rescue ActiveRecord::InvalidForeignKey
        flunk "FK constraint violated: job was deleted despite having an associated job run"
      end

      assert RailsPulse::Job.exists?(old_job.id),
        "Job was deleted despite having an associated job run"
    end

    # Foreign Key Safety Tests

    test "time-based cleanup does not raise FK violation when job run operation has newer occurred_at than job run" do
      RailsPulse.configuration.full_retention_period = 30.days

      old_job = create_job("FKTimeJob")
      old_run = create_job_run(old_job, occurred_at: 40.days.ago)
      create_operation(job_run: old_run, occurred_at: 5.days.ago)

      assert_nothing_raised do
        CleanupService.perform
      end
    end

    test "count-based cleanup does not raise FK violation when job runs have associated operations" do
      RailsPulse.configuration.max_table_records = {
        rails_pulse_operations: 10_000,  # high — operations won't be deleted
        rails_pulse_requests:   10_000,
        rails_pulse_job_runs:   1,       # low — oldest job_run will be a deletion target
        rails_pulse_queries:    10_000,
        rails_pulse_routes:     10_000,
        rails_pulse_jobs:       10_000
      }
      RailsPulse.configuration.instance_variable_set(:@full_retention_period, nil)

      create_overall_hourly_summary(period_end: 2.hours.ago)

      job = create_job("FKCountJob")
      old_run = create_job_run(job, occurred_at: 3.hours.ago)
      create_operation(job_run: old_run, occurred_at: 3.hours.ago)
      create_job_run(job, occurred_at: 30.minutes.ago)  # newer run keeps count at 2 > max of 1

      assert_nothing_raised do
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

    def create_overall_hourly_summary(period_end:)
      period_start = period_end.beginning_of_hour
      RailsPulse::Summary.create!(
        summarizable_type: "RailsPulse::Request",
        summarizable_id:   0,
        period_type:       "hour",
        period_start:      period_start,
        period_end:        period_end,
        count:             1,
        avg_duration:      100.0
      )
    end

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
