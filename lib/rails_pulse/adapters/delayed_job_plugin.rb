require_relative "job_wrapper"

module RailsPulse
  module Adapters
    class DelayedJobPlugin < Delayed::Plugin
      callbacks do |lifecycle|
        lifecycle.around(:perform) do |worker, job_data, &block|
          next block.call(worker, job_data) unless RailsPulse.configuration.enabled
          next block.call(worker, job_data) unless RailsPulse.configuration.track_jobs

          payload = job_data.payload_object
          arguments = if payload.respond_to?(:args)
                        payload.args
          elsif payload.respond_to?(:arguments)
                        payload.arguments
          else
                        []
          end

          job_wrapper = RailsPulse::Adapters::JobWrapper.new(
            job_id: job_data.id.to_s,
            class_name: payload.class.name,
            queue_name: job_data.queue,
            arguments: arguments,
            enqueued_at: job_data.created_at,
            executions: job_data.attempts
          )

          RailsPulse::JobRunCollector.track(job_wrapper, adapter: "delayed_job") do
            block.call(worker, job_data)
          end
        end
      end
    end
  end
end
