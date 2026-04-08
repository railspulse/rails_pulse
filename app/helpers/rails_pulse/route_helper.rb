module RailsPulse
  module RouteHelper
    # Make Rails Pulse routes available as rails_pulse in views
    # Example: rails_pulse.routes_path
    def rails_pulse
      @rails_pulse_helper ||= RailsPulseHelper.new(self)
    end

    # Helper class to provide both routes and asset methods
    class RailsPulseHelper
      def initialize(view_context)
        @view_context = view_context
      end

      # Delegate route methods to engine routes
      def method_missing(method, *args, &block)
        if RailsPulse::Engine.routes.url_helpers.respond_to?(method)
          RailsPulse::Engine.routes.url_helpers.send(method, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        RailsPulse::Engine.routes.url_helpers.respond_to?(method, include_private) || super
      end

      # Generate asset paths using Rails asset pipeline
      # This allows assets to work with CDN, digests, and precompiled manifests
      def asset_path(asset_name)
        # Only use asset pipeline if we have Sprockets/Propshaft configured
        # Otherwise fall back to middleware serving
        if defined?(::Sprockets) || defined?(::Propshaft)
          # Use the main application's asset_path helper to ensure we get
          # the correct digested paths from the precompiled manifest
          begin
            ActionController::Base.helpers.asset_path(asset_name)
          rescue => e
            # Fallback to direct path if asset pipeline is not available
            Rails.logger.warn "[Rails Pulse] Asset pipeline error for #{asset_name}: #{e.message}"
            "/rails-pulse-assets/#{asset_name}"
          end
        else
          # No asset pipeline - use middleware serving
          "/rails-pulse-assets/#{asset_name}"
        end
      end
    end
  end
end
