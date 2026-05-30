require "securerandom"

require "test_helper"

module RailsPulse
  class JobRunCollectorTest < ActiveSupport::TestCase
    class FakeJob
      attr_reader :job_id, :queue_name, :executions

      def initialize(job_id: SecureRandom.uuid, queue_name: "default", executions: 0)
        @job_id = job_id
        @queue_name = queue_name
        @executions = executions
      end

      def self.name
        "JobRunCollectorFakeJob"
      end

      def arguments
        [ 1, 2, 3 ]
      end

      def enqueued_at
        Time.current
      end
    end

    setup do
      RequestStore.clear!
      @original_capture_arguments = RailsPulse.configuration.capture_job_arguments
      @original_ignored_jobs      = RailsPulse.configuration.ignored_jobs
      @original_ignored_queues    = RailsPulse.configuration.ignored_queues
      RailsPulse.configuration.capture_job_arguments = true
      RailsPulse.configuration.ignored_jobs           = []
      RailsPulse.configuration.ignored_queues         = []
    end

    teardown do
      RequestStore.clear!
      RailsPulse.configuration.capture_job_arguments = @original_capture_arguments
      RailsPulse.configuration.ignored_jobs           = @original_ignored_jobs
      RailsPulse.configuration.ignored_queues         = @original_ignored_queues
    end

    test "track records job run and operations" do
      job = FakeJob.new

      assert_difference -> { RailsPulse::Job.count }, 1 do
        assert_difference -> { RailsPulse::JobRun.count }, 1 do
          RailsPulse::JobRunCollector.track(job) do
            ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT 1") do
              sleep(0.001)
            end
          end
        end
      end

      job_run = RailsPulse::JobRun.order(:created_at).last

      assert_equal FakeJob.name, job_run.job.name
      assert_equal "success", job_run.status
      assert_equal job.job_id, job_run.run_id
      assert_equal job.queue_name, job_run.job.queue_name
      assert_not_nil job_run.duration
      assert_equal "[1,2,3]", job_run.arguments

      operations = RailsPulse::Operation.where(job_run: job_run)

      assert_equal 1, operations.count
      assert_nil operations.first.request_id
    end

    test "track marks failures and surfaces exceptions" do
      job = FakeJob.new

      assert_raises RuntimeError do
        RailsPulse::JobRunCollector.track(job) do
          raise RuntimeError, "boom"
        end
      end

      job_run = RailsPulse::JobRun.order(:created_at).last

      assert_equal "failed", job_run.status
      assert_equal "RuntimeError", job_run.error_class
      assert_equal "boom", job_run.error_message
    end

    test "track handles job retries with same job_id" do
      job_id = SecureRandom.uuid
      first_job = FakeJob.new(job_id: job_id, executions: 1)

      RailsPulse::JobRunCollector.track(first_job) do
        # First execution succeeds
      end

      first_run = RailsPulse::JobRun.find_by(run_id: job_id)

      assert_equal "success", first_run.status
      assert_equal 1, first_run.attempts

      retry_job = FakeJob.new(job_id: job_id, executions: 2)

      assert_no_difference -> { RailsPulse::JobRun.count } do
        RailsPulse::JobRunCollector.track(retry_job) do
          # Retry execution
        end
      end

      retry_run = RailsPulse::JobRun.find_by(run_id: job_id)

      assert_equal "success", retry_run.status
      assert_equal 2, retry_run.attempts
      assert_equal first_run.id, retry_run.id
    end

    # Filtering Tests

    test "track skips job in ignored_jobs list" do
      RailsPulse.configuration.ignored_jobs = [ FakeJob.name ]

      assert_no_difference -> { RailsPulse::JobRun.count } do
        RailsPulse::JobRunCollector.track(FakeJob.new) { }
      end
    end

    test "track skips job in ignored_queues list" do
      RailsPulse.configuration.ignored_queues = [ "default" ]

      assert_no_difference -> { RailsPulse::JobRun.count } do
        RailsPulse::JobRunCollector.track(FakeJob.new) { }
      end
    end

    test "track does not capture arguments when capture_job_arguments is false" do
      RailsPulse.configuration.capture_job_arguments = false

      RailsPulse::JobRunCollector.track(FakeJob.new) { }

      run = RailsPulse::JobRun.order(:created_at).last

      assert_nil run.arguments
    end

    # Race Condition Tests

    test "find_or_create_job creates new job record" do
      RailsPulse::Job.where(name: FakeJob.name).delete_all

      job = RailsPulse::JobRunCollector.send(:find_or_create_job, FakeJob.new)

      assert_equal FakeJob.name, job.name
      assert_equal "default", job.queue_name
      assert_predicate job, :persisted?
    end

    test "find_or_create_job finds existing job record" do
      RailsPulse::Job.where(name: FakeJob.name).delete_all
      existing = RailsPulse::Job.create!(name: FakeJob.name, queue_name: "default")

      result = RailsPulse::JobRunCollector.send(:find_or_create_job, FakeJob.new)

      assert_equal existing.id, result.id
    end

    test "find_or_create_job recovers from RecordNotUnique" do
      RailsPulse::Job.where(name: FakeJob.name).delete_all

      RailsPulse::Job.create!(name: FakeJob.name, queue_name: "default")

      RailsPulse::Job.define_singleton_method(:find_or_create_by!) do |*args, **kwargs, &block|
        raise ActiveRecord::RecordNotUnique, "duplicate"
      end

      result = RailsPulse::JobRunCollector.send(:find_or_create_job, FakeJob.new)

      assert_equal FakeJob.name, result.name
    ensure
      RailsPulse::Job.singleton_class.remove_method(:find_or_create_by!) rescue nil
    end

    test "create_job_run creates new job run record" do
      job = rails_pulse_jobs(:mailer_job)
      fake = FakeJob.new
      fake.instance_variable_set(:@job_id, "unique-run-#{SecureRandom.hex(4)}")

      run = RailsPulse::JobRunCollector.send(:create_job_run, job, fake, "test", Time.current)

      assert_predicate run, :persisted?
      assert_equal fake.job_id, run.run_id
    end

    test "create_job_run recovers from RecordNotUnique" do
      job = rails_pulse_jobs(:mailer_job)
      fake = FakeJob.new
      run_id = "race-run-#{SecureRandom.hex(4)}"
      fake.instance_variable_set(:@job_id, run_id)

      existing = RailsPulse::JobRun.create!(run_id: run_id, job: job, status: "running", occurred_at: Time.current)

      RailsPulse::JobRun.define_singleton_method(:create_or_find_by) do |*args, **kwargs, &block|
        raise ActiveRecord::RecordNotUnique, "duplicate"
      end

      result = RailsPulse::JobRunCollector.send(:create_job_run, job, fake, "test", Time.current)

      assert_equal existing.id, result.id
    ensure
      RailsPulse::JobRun.singleton_class.remove_method(:create_or_find_by) rescue nil
    end

    test "active job integration wraps perform now" do
      klass = Class.new(ActiveJob::Base) do
        queue_as :default

        def perform
          ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT 1") do
            sleep(0.001)
          end
        end
      end

      if Object.const_defined?(:JobRunCollectorTestInstrumentedJob)
        Object.send(:remove_const, :JobRunCollectorTestInstrumentedJob)
      end

      Object.const_set(:JobRunCollectorTestInstrumentedJob, klass)

      assert_difference -> { RailsPulse::Job.where(name: JobRunCollectorTestInstrumentedJob.name).count }, 1 do
        assert_difference -> { RailsPulse::JobRun.count }, 1 do
          JobRunCollectorTestInstrumentedJob.perform_now
        end
      end

      job = RailsPulse::Job.find_by(name: JobRunCollectorTestInstrumentedJob.name)

      assert_not_nil job
      run = job.runs.order(:created_at).last

      assert_equal "success", run.status
      assert_not_empty RailsPulse::Operation.where(job_run: run)
    ensure
      if Object.const_defined?(:JobRunCollectorTestInstrumentedJob)
        Object.send(:remove_const, :JobRunCollectorTestInstrumentedJob)
      end
    end
  end
end
