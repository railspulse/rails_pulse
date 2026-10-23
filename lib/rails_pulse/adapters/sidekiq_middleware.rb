require_relative "job_wrapper"

module RailsPulse
  module Adapters
    class SidekiqMiddleware
      def call(worker, job_data, queue)
        return yield unless RailsPulse.configuration.enabled
        return yield unless RailsPulse.configuration.track_jobs
        # Active Job jobs arrive wrapped (Sidekiq::ActiveJob::Wrapper, or
        # ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper before Sidekiq 7.3)
        # with the real class in "wrapped". ActiveJobExtensions already tracks
        # them, so tracking the wrapper too would count every run twice.
        return yield if job_data["wrapped"]

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
  end
end
