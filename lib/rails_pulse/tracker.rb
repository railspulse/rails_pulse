require "async"

module RailsPulse
  module Tracker
    class << self
      def track_request(data)
        return if RequestStore.store[:skip_recording_rails_pulse_activity]

        if RailsPulse.configuration.async
          Async { perform_tracking(data) }
        else
          perform_tracking(data)
        end
      end

      def healthy?
        RailsPulse::ApplicationRecord.connection.execute("SELECT 1")
        true
      rescue
        false
      end

      private

      def perform_tracking(data)
        RailsPulse::ApplicationRecord.connection_pool.with_connection do
          RequestStore.store[:skip_recording_rails_pulse_activity] = true

          route = RailsPulse::Route.by_method_and_path(data[:method], data[:path])

          request = RailsPulse::Request.create!(
            route: route,
            duration: data[:duration],
            status: data[:status],
            is_error: data[:is_error],
            request_uuid: data[:request_uuid],
            controller_action: data[:controller_action],
            occurred_at: data[:occurred_at],
            response_size_bytes: data[:response_size_bytes]
          )

          ops = data[:operations] || []
          RailsPulse::Operation.persist_bulk(ops, request_id: request.id)

          request
        rescue => e
          log_error(e)
          nil
        ensure
          RequestStore.store[:skip_recording_rails_pulse_activity] = false
        end
      end

      def log_error(error)
        RailsPulse.logger.error("Failed to persist tracking data: #{error.message}")
        RailsPulse.logger.error(error.backtrace.join("\n")) if RailsPulse.logger.debug?
      end
    end
  end
end
