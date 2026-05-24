require "test_helper"

module RailsPulse
  class JobTest < ActiveSupport::TestCase
    test "validations" do
      job = Job.new

      assert_not job.valid?
      assert_includes job.errors[:name], "can't be blank"
    end

    test "database unique index enforces name uniqueness" do
      existing = rails_pulse_jobs(:mailer_job)

      duplicate = Job.new(name: existing.name)

      assert_predicate duplicate, :valid?
      assert_raises ActiveRecord::RecordNotUnique do
        duplicate.save!(validate: false)
      end
    end

    test "failure rate calculation" do
      job = rails_pulse_jobs(:report_job)

      assert_in_delta(50.0, job.failure_rate)
    end

    test "apply_run! updates aggregates" do
      job = Job.create!(name: "RailsPulse::TestJob", queue_name: "default")
      run = job.runs.create!(run_id: "test-run-1", status: "running", occurred_at: Time.current, attempts: 0)

      run.update_columns(status: "retried", duration: 200.0)

      job.apply_run!(run.reload)
      job.reload

      assert_in_delta 200.0, job.avg_duration, 0.01
      assert_equal 1, job.failures_count
      assert_equal 1, job.retries_count
    end

    test "apply_run! persists p95 and p99 when a single run exists" do
      job = Job.create!(name: "PercentileJob::SingleRun", queue_name: "default")
      run = job.runs.create!(run_id: "single-pctile", status: "success",
                              occurred_at: Time.current, attempts: 1, duration: 500.0)

      job.apply_run!(run)
      job.reload

      # With one data point both percentiles equal the single value
      assert_in_delta 500.0, job.p95_duration, 0.01
      assert_in_delta 500.0, job.p99_duration, 0.01
    end

    test "apply_run! calculates correct p95 and p99 across multiple runs" do
      job = Job.create!(name: "PercentileJob::MultiRun", queue_name: "default")

      # 10 runs with durations 100ms through 1000ms in 100ms steps
      # Sorted ascending: [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
      10.times do |i|
        job.runs.create!(
          run_id: "multi-pctile-#{i}",
          status: "success",
          occurred_at: i.minutes.ago,
          attempts: 1,
          duration: (i + 1) * 100.0
        )
      end

      last_run = job.runs.order(occurred_at: :desc).first
      job.apply_run!(last_run)
      job.reload

      # P95: n=10, rank = 0.95*9 = 8.55 → lerp(900, 1000, 0.55) = 955ms
      assert_in_delta 955.0, job.p95_duration, 1.0
      # P99: n=10, rank = 0.99*9 = 8.91 → lerp(900, 1000, 0.91) = 991ms
      assert_in_delta 991.0, job.p99_duration, 1.0
    end

    test "apply_run! produces equal p95 and p99 when all run durations are identical" do
      job = Job.create!(name: "PercentileJob::AllSame", queue_name: "default")

      5.times do |i|
        job.runs.create!(
          run_id: "same-dur-#{i}",
          status: "success",
          occurred_at: i.minutes.ago,
          attempts: 1,
          duration: 300.0
        )
      end

      last_run = job.runs.order(occurred_at: :desc).first
      job.apply_run!(last_run)
      job.reload

      assert_in_delta 300.0, job.p95_duration, 0.01
      assert_in_delta 300.0, job.p99_duration, 0.01
    end

    test "apply_run! ignores nil-duration runs when calculating percentiles" do
      job = Job.create!(name: "PercentileJob::NilDuration", queue_name: "default")

      # Runs without duration (e.g., still enqueued) must not affect percentile
      job.runs.create!(run_id: "nil-dur-1", status: "running", occurred_at: 2.minutes.ago, attempts: 1)
      job.runs.create!(run_id: "nil-dur-2", status: "running", occurred_at: 1.minute.ago, attempts: 1)

      run = job.runs.create!(run_id: "with-dur-1", status: "success",
                              occurred_at: Time.current, attempts: 1, duration: 300.0)

      job.apply_run!(run)
      job.reload

      assert_in_delta 300.0, job.p95_duration, 0.01
      assert_in_delta 300.0, job.p99_duration, 0.01
    end

    test "apply_run! uses only the 100 most recent runs for percentile calculation" do
      job = Job.create!(name: "PercentileJob::Cap", queue_name: "default")

      # 10 older outlier runs that would skew percentiles if included
      10.times do |i|
        job.runs.create!(
          run_id: "old-run-#{i}",
          status: "success",
          occurred_at: (120 - i).minutes.ago,
          attempts: 1,
          duration: 10_000.0
        )
      end

      # 100 recent runs with a consistent normal duration
      last_run = nil
      100.times do |i|
        last_run = job.runs.create!(
          run_id: "recent-run-#{i}",
          status: "success",
          occurred_at: (99 - i).minutes.ago,
          attempts: 1,
          duration: 200.0
        )
      end

      job.apply_run!(last_run)
      job.reload

      # Only the 100 most recent runs (all 200ms) should be used; outliers excluded
      assert_in_delta 200.0, job.p95_duration, 0.01
      assert_in_delta 200.0, job.p99_duration, 0.01
    end

    test "performance_status respects thresholds" do
      job = Job.create!(name: "ThresholdJob", avg_duration: 0, queue_name: "default")
      original_thresholds = RailsPulse.configuration.job_thresholds.dup

      RailsPulse.configuration.job_thresholds = { slow: 100, very_slow: 500, critical: 1000 }

      job.update!(avg_duration: 50)

      assert_equal :fast, job.performance_status

      job.update!(avg_duration: 200)

      assert_equal :slow, job.performance_status

      job.update!(avg_duration: 700)

      assert_equal :very_slow, job.performance_status

      job.update!(avg_duration: 1_500)

      assert_equal :critical, job.performance_status
    ensure
      RailsPulse.configuration.job_thresholds = original_thresholds
    end
  end
end
