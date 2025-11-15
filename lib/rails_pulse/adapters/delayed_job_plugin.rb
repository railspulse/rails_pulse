module RailsPulse
  module Adapters
    class DelayedJobPlugin < Delayed::Plugin
      callbacks do |lifecycle|
        lifecycle.around(:perform) do |worker, job_data, &block|
          next block.call(worker, job_data) unless RailsPulse.configuration.enabled
          next block.call(worker, job_data) unless RailsPulse.configuration.track_jobs

          job_wrapper = JobWrapper.new(
            job_id: job_data.id.to_s,
            class_name: job_data.payload_object.class.name,
            queue_name: job_data.queue,
            arguments: job_data.payload_object.args,
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
