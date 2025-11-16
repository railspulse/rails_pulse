require "test_helper"

module RailsPulse
  class JobTest < ActiveSupport::TestCase
    test "validations" do
      job = Job.new

      assert_not job.valid?
      assert_includes job.errors[:name], "can't be blank"

      duplicate = Job.new(name: rails_pulse_jobs(:mailer_job).name)

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:name], "has already been taken"
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
