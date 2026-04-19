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

      def perform_tracking(data, retry_count = 0)
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
              occurred_at: data[:occurred_at],
              response_size_bytes: data[:response_size_bytes]
            )

            # Create operation records
            (data[:operations] || []).each do |op_data|
              RailsPulse::Operation.create!(op_data.merge(request_id: request.id))
            end

            request
          rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid => e
            # Retry transient database errors with exponential backoff
            if retry_count < 2
              sleep(0.1 * (2**retry_count))  # 0.1s, 0.2s
              perform_tracking(data, retry_count + 1)
            else
              log_error(e, retry_count)
              nil
            end
          rescue => e
            log_error(e, retry_count)
            nil  # Don't raise - never fail main request
          ensure
            RequestStore.store[:skip_recording_rails_pulse_activity] = false
          end
        end
      end

      def log_error(error, retry_count = 0)
        retry_info = retry_count > 0 ? " (after #{retry_count} retries)" : ""
        RailsPulse.logger.error("Failed to persist tracking data#{retry_info}: #{error.message}")
        RailsPulse.logger.error(error.backtrace.join("\n")) if RailsPulse.logger.debug?
      end
    end
  end
end
