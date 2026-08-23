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

      # After `assets:precompile`, files live in public/assets with a digest
      # so config.asset_host / CDN-only CSP work. Until then (development,
      # or hosts with no pipeline) serve from the gem via AssetServer.
      # Always pass the result to tag.link / tag.script, not stylesheet_link_tag:
      # a middleware path must not be rewritten onto the CDN.
      def asset_path(asset_name)
        if (packaged = RailsPulse::PackagedAssets.url_path(asset_name))
          ActionController::Base.helpers.asset_path(packaged)
        else
          "/rails-pulse-assets/#{RailsPulse::VERSION}/#{asset_name}"
        end
      end
    end
  end
end
