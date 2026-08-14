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

      # Assets are pre-built into the gem's public directory and served by
      # the AssetServer middleware, so no host asset pipeline is involved.
      def asset_path(asset_name)
        "/rails-pulse-assets/#{asset_name}"
      end
    end
  end
end
