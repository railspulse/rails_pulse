require "securerandom"

module RailsPulse
  class JobRunCollector
    class << self
      def track(active_job, adapter: detect_adapter)
        return yield unless tracking_enabled?
        return yield if ignore_job?(active_job)

        previous_request_id = RequestStore.store[:rails_pulse_request_id]
        previous_operations = RequestStore.store[:rails_pulse_operations]
        previous_job_run_id = RequestStore.store[:rails_pulse_job_run_id]

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        occurred_at = Time.current

        job = nil
        job_run = nil

        with_recording_suppressed do
          job = find_or_create_job(active_job)
          job_run = create_job_run(job, active_job, adapter, occurred_at)
        end

        RequestStore.store[:rails_pulse_request_id] = nil
        RequestStore.store[:rails_pulse_job_run_id] = job_run.id
        RequestStore.store[:rails_pulse_operations] = []

        yield

        duration = elapsed_time_ms(start_time)
        with_recording_suppressed do
          job_run.update!(status: "success", duration: duration)
        end
      rescue => error
        duration = elapsed_time_ms(start_time)
        with_recording_suppressed do
          job_run.update!(
            status: failure_status_for(error),
            duration: duration,
            error_class: error.class.name,
            error_message: error.message
          ) if job_run
        end
        raise
      ensure
        begin
          save_operations(job_run)
        rescue => e
          Rails.logger.error "[RailsPulse] Failed to persist job operations: #{e.class} - #{e.message}"
        ensure
          RequestStore.store[:rails_pulse_job_run_id] = previous_job_run_id
          RequestStore.store[:rails_pulse_operations] = previous_operations
          RequestStore.store[:rails_pulse_request_id] = previous_request_id
        end
      end

      def should_ignore_job?(job)
        ignore_job?(job)
      end

      private

      def tracking_enabled?
        config = RailsPulse.configuration
        config.enabled && config.track_jobs
      end

      def ignore_job?(job)
        config = RailsPulse.configuration
        job_class = job.class.name
        queue_name = job.queue_name

        return true if config.ignored_jobs&.include?(job_class)
        return true if config.ignored_queues&.include?(queue_name)
        return true if job_class.start_with?("RailsPulse::")

        false
      end

      def find_or_create_job(active_job)
        RailsPulse::Job.find_or_create_by!(name: active_job.class.name) do |job|
          job.queue_name = active_job.queue_name
        end
      end

      def create_job_run(job, active_job, adapter, occurred_at)
        RailsPulse::JobRun.create!(
          job: job,
          run_id: active_job.job_id || SecureRandom.uuid,
          status: initial_status_for(active_job),
          enqueued_at: safe_timestamp(active_job.try(:enqueued_at)),
          occurred_at: occurred_at,
          attempts: (active_job.respond_to?(:executions) ? active_job.executions : 0),
          adapter: adapter,
          arguments: serialized_arguments(active_job)
        )
      end

      def serialized_arguments(active_job)
        return unless RailsPulse.configuration.capture_job_arguments

        Array(active_job.arguments).to_json
      rescue StandardError => e
        Rails.logger.debug "[RailsPulse] Unable to serialize job arguments: #{e.class} - #{e.message}"
        nil
      end

      def initial_status_for(active_job)
        active_job.respond_to?(:scheduled_at) ? "enqueued" : "running"
      end

      def failure_status_for(error)
        error.is_a?(StandardError) ? "failed" : "discarded"
      end

      def save_operations(job_run)
        return unless job_run

        operations_data = RequestStore.store[:rails_pulse_operations] || []
        operations_data.each do |operation_data|
          operation_data[:job_run_id] = job_run.id
          operation_data[:request_id] = nil

          with_recording_suppressed do
            RailsPulse::Operation.create!(operation_data)
          end
        rescue => e
          Rails.logger.error "[RailsPulse] Failed to save job operation: #{e.class} - #{e.message}"
        end
      ensure
        RequestStore.store[:rails_pulse_operations] = nil
      end

      def detect_adapter
        return "sidekiq" if defined?(::Sidekiq)
        return "solid_queue" if defined?(::SolidQueue)
        return "good_job" if defined?(::GoodJob)
        return "delayed_job" if defined?(::Delayed::Job)
        return "resque" if defined?(::Resque)
        return "que" if defined?(::Que)

        "active_job"
      end

      def elapsed_time_ms(start_time)
        return 0.0 unless start_time

        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
      end

      def safe_timestamp(value)
        case value
        when Time, ActiveSupport::TimeWithZone
          value
        when Integer
          Time.at(value)
        else
          nil
        end
      end

      def with_recording_suppressed
        previous = RequestStore.store[:skip_recording_rails_pulse_activity]
        RequestStore.store[:skip_recording_rails_pulse_activity] = true
        yield
      ensure
        RequestStore.store[:skip_recording_rails_pulse_activity] = previous
      end
    end
  end
end
