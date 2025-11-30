module RailsPulse
  module Tracker
    class << self
      def track_request(data)
        return if RequestStore.store[:skip_recording_rails_pulse_activity]

        if RailsPulse.configuration.async
          # Async mode - spawn background thread
          Thread.new do
            perform_tracking(data)
          end
        else
          # Sync mode - blocking write
          perform_tracking(data)
        end
      end

      def healthy?
        # Simple health check - can we connect to database?
        begin
          RailsPulse::ApplicationRecord.connection.active?
        rescue
          false
        end
      end

      private

      def perform_tracking(data)
        RailsPulse::ApplicationRecord.connection_pool.with_connection do
          # Set recursion prevention flag
          RequestStore.store[:skip_recording_rails_pulse_activity] = true

          begin
            # Find or create route
            route = RailsPulse::Route.find_or_create_by(
              method: data[:method],
              path: data[:path]
            )

            # Create request record
            request = RailsPulse::Request.create!(
              route: route,
              duration: data[:duration],
              status: data[:status],
              is_error: data[:is_error],
              request_uuid: data[:request_uuid],
              controller_action: data[:controller_action],
              occurred_at: data[:occurred_at]
            )

            # Create operation records
            (data[:operations] || []).each do |op_data|
              RailsPulse::Operation.create!(op_data.merge(request_id: request.id))
            end

            request
          rescue => e
            log_error(e)
            nil  # Don't raise - never fail main request
          ensure
            RequestStore.store[:skip_recording_rails_pulse_activity] = false
          end
        end
      end

      def log_error(error)
        logger = RailsPulse.configuration.logger || Rails.logger
        logger&.error("[RailsPulse] Failed to persist tracking data: #{error.message}")
        logger&.error(error.backtrace.join("\n")) if logger&.debug?
      end
    end
  end
end
