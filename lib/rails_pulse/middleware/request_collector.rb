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

        # Clear any previous request ID to avoid conflicts
        RequestStore.store[:rails_pulse_request_id] = nil

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Temporarily skip recording while we create the route and request
        RequestStore.store[:skip_recording_rails_pulse_activity] = true
        route = find_or_create_route(req)
        controller_action = "#{env['action_dispatch.request.parameters']&.[]('controller')&.classify}##{env['action_dispatch.request.parameters']&.[]('action')}"
        occurred_at = Time.current

        request = nil
        if route
          request = RailsPulse::Request.create!(
            route: route,
            duration: 0, # will update after response
            status: 0, # will update after response
            is_error: false,
            request_uuid: req.uuid,
            controller_action: controller_action,
            occurred_at: occurred_at
          )
          RequestStore.store[:rails_pulse_request_id] = request.id
        end

        # Re-enable recording for the actual request processing
        RequestStore.store[:skip_recording_rails_pulse_activity] = false

        status, headers, response = @app.call(env)
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        # Temporarily skip recording while we update the request and save operations
        RequestStore.store[:skip_recording_rails_pulse_activity] = true
        if request
          request.update(duration: duration, status: status, is_error: status.to_i >= 500)

          # Save collected operations
          operations_data = RequestStore.store[:rails_pulse_operations] || []
          operations_data.each do |operation_data|
            begin
              RailsPulse::Operation.create!(operation_data)
            rescue => e
              Rails.logger.error "[RailsPulse] Failed to save operation: #{e.message}"
            end
          end
        end

        [ status, headers, response ]
      ensure
        RequestStore.store[:skip_recording_rails_pulse_activity] = false
        RequestStore.store[:rails_pulse_request_id] = nil
        RequestStore.store[:rails_pulse_operations] = nil
      end

      private

      def find_or_create_route(req)
        method = req.request_method
        path = req.path
        RailsPulse::Route.find_or_create_by(method: method, path: path)
      end

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
