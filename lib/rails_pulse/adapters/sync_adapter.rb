module RailsPulse
  module Adapters
    class SyncAdapter < BaseAdapter
      # Current behavior - direct DB writes during request
      def track_request(data)
        # Skip if tracking is disabled (recursion prevention)
        return if RequestStore.store[:skip_recording_rails_pulse_activity]

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
          Rails.logger.error "[RailsPulse::SyncAdapter] Failed to persist tracking data: #{e.message}"
          raise
        ensure
          RequestStore.store[:skip_recording_rails_pulse_activity] = false
        end
      end
    end
  end
end
