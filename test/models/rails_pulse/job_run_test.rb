require "test_helper"

module RailsPulse
  class JobRunTest < ActiveSupport::TestCase
    test "validations" do
      run = JobRun.new

      assert_not run.valid?
      assert_includes run.errors[:job], "must exist"
      assert_includes run.errors[:run_id], "can't be blank"
      assert_includes run.errors[:status], "is not included in the list"
      assert_includes run.errors[:occurred_at], "can't be blank"
    end

    test "all_tags combines job and run tags" do
      job = rails_pulse_jobs(:report_job)
      job.update!(tags: '["critical"]')

      run = rails_pulse_job_runs(:report_run_retried)
      run.update!(tags: '["retry"]')

      assert_equal %w[critical retry], run.all_tags.sort
    end

    test "performance_status uses job thresholds" do
      run = rails_pulse_job_runs(:report_run_success)
      original_thresholds = RailsPulse.configuration.job_thresholds.dup
      RailsPulse.configuration.job_thresholds = { slow: 100, very_slow: 500, critical: 1_000 }

      run.update!(duration: 50)

      assert_equal :fast, run.performance_status

      run.update!(duration: 300)

      assert_equal :slow, run.performance_status

      run.update!(duration: 700)

      assert_equal :very_slow, run.performance_status

      run.update!(duration: 1_200)

      assert_equal :critical, run.performance_status
    ensure
      RailsPulse.configuration.job_thresholds = original_thresholds
    end

    test "finalized? detects transition to final status" do
      job = RailsPulse::Job.create!(name: "CallbackTestJob")
      run = job.runs.create!(run_id: "callback-run", status: "running", occurred_at: Time.current)

      run.update!(status: "success", duration: 25.0)

      assert_predicate run, :finalized?
      assert_not run.failure_like_status?

      run.update!(status: "retried", duration: 50.0)

      assert_not run.finalized?, "transition between final states should not trigger"
      assert_predicate run, :failure_like_status?
    end
  end
end
