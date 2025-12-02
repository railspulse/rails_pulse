module RailsPulse
  module Middleware
    class RequestCollector
      def initialize(app)
        @app = app
      end

      def call(env)
        # Skip if Rails Pulse is disabled
        return @app.call(env) unless RailsPulse.configuration.enabled

        # Skip logging if we are already recording RailsPulse activity. This is to avoid recursion issues
        return @app.call(env) if RequestStore.store[:skip_recording_rails_pulse_activity]

        req = ActionDispatch::Request.new(env)

        # Skip RailsPulse engine requests
        mount_path = RailsPulse.configuration.mount_path || "/rails_pulse"
        if req.path.start_with?(mount_path)
          RequestStore.store[:skip_recording_rails_pulse_activity] = true
          result = @app.call(env)
          RequestStore.store[:skip_recording_rails_pulse_activity] = false
          return result
        end

        # Check if route should be ignored based on configuration
        if should_ignore_route?(req)
          RequestStore.store[:skip_recording_rails_pulse_activity] = true
          result = @app.call(env)
          RequestStore.store[:skip_recording_rails_pulse_activity] = false
          return result
        end

        # Clear any previous request data
        RequestStore.store[:rails_pulse_request_id] = nil
        RequestStore.store[:rails_pulse_operations] = []

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        controller_action = "#{env['action_dispatch.request.parameters']&.[]('controller')&.classify}##{env['action_dispatch.request.parameters']&.[]('action')}"
        occurred_at = Time.current

        # Process request
        status, headers, response = @app.call(env)
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        # Collect all tracking data
        # Deep copy operations array to prevent race condition in async mode
        operations = RequestStore.store[:rails_pulse_operations] || []
        tracking_data = {
          method: req.request_method,
          path: req.path,
          duration: duration,
          status: status,
          is_error: status.to_i >= 500,
          request_uuid: req.uuid,
          controller_action: controller_action,
          occurred_at: occurred_at,
          operations: operations.map(&:dup)
        }

        # Send to tracker (non-blocking if async mode enabled)
        RailsPulse::Tracker.track_request(tracking_data)

        [ status, headers, response ]
      ensure
        RequestStore.store[:skip_recording_rails_pulse_activity] = false
        RequestStore.store[:rails_pulse_request_id] = nil
        RequestStore.store[:rails_pulse_operations] = nil
      end

      private

      def should_ignore_route?(req)
        # Get ignored routes from configuration
        ignored_routes = RailsPulse.configuration.ignored_routes || []

        # Create route identifier for matching
        route_method_path = "#{req.request_method} #{req.path}"
        route_path = req.path

        # Check each ignored route pattern
        ignored_routes.any? do |pattern|
          case pattern
          when String
            # Exact string match against path or method+path
            pattern == route_path || pattern == route_method_path
          when Regexp
            # Regex match against path or method+path
            pattern.match?(route_path) || pattern.match?(route_method_path)
          else
            false
          end
        end
      end
    end
  end
end
