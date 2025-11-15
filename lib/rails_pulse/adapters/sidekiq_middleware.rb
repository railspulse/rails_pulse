module RailsPulse
  module Adapters
    class SidekiqMiddleware
      def call(worker, job_data, queue)
        return yield unless RailsPulse.configuration.enabled
        return yield unless RailsPulse.configuration.track_jobs

        # Create ActiveJob-like wrapper for tracking
        job_wrapper = JobWrapper.new(
          job_id: job_data["jid"],
          class_name: worker.class.name,
          queue_name: queue,
          arguments: job_data["args"],
          enqueued_at: Time.at(job_data["enqueued_at"] || Time.current.to_f),
          executions: job_data["retry_count"] || 0
        )

        RailsPulse::JobRunCollector.track(job_wrapper, adapter: "sidekiq") do
          yield
        end
      end
    end

    class JobWrapper
      attr_reader :job_id, :queue_name, :arguments, :enqueued_at, :executions

      def initialize(job_id:, class_name:, queue_name:, arguments:, enqueued_at:, executions:)
        @job_id = job_id
        @class_name = class_name
        @queue_name = queue_name
        @arguments = arguments
        @enqueued_at = enqueued_at
        @executions = executions
      end

      def class
        OpenStruct.new(name: @class_name)
      end
    end
  end
end
