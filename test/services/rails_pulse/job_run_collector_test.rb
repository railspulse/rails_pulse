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
      RailsPulse.configuration.capture_job_arguments = true
    end

    teardown do
      RequestStore.clear!
      RailsPulse.configuration.capture_job_arguments = @original_capture_arguments
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
