module RailsPulse
  module ApplicationHelper
    include BreadcrumbsHelper
    include ChartHelper
    include FormattingHelper
    include StatusHelper
    include TableHelper
    include FormHelper
    include TagsHelper

    # Replacement for lucide_icon helper that works with pre-compiled assets
    # Outputs a custom element that will be hydrated by Stimulus
    def rails_pulse_icon(name, options = {})
      width = options[:width] || options["width"] || 24
      height = options[:height] || options["height"] || 24
      css_class = options[:class] || options["class"] || ""

      # Additional HTML attributes
      attrs = options.except(:width, :height, :class, "width", "height", "class")

      content_tag("rails-pulse-icon",
        "",
        data: {
          controller: "rails-pulse--icon",
          'rails-pulse--icon-name-value': name,
          'rails-pulse--icon-width-value': width,
          'rails-pulse--icon-height-value': height
        },
        class: css_class,
        **attrs
      )
    end

    # Backward compatibility alias - can be removed after migration
    alias_method :lucide_icon, :rails_pulse_icon

    # Make Rails Pulse routes available as rails_pulse in views
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

      # Generate asset paths that work with our custom asset serving
      def asset_path(asset_name)
        "/rails-pulse-assets/#{asset_name}"
      end
    end

    # CSP nonce helper for Rails Pulse
    def rails_pulse_csp_nonce
      # Try various methods to get the CSP nonce from the host application
      nonce = nil

      # Method 1: Check for Rails 6+ CSP nonce helper
      if respond_to?(:content_security_policy_nonce)
        nonce = content_security_policy_nonce
      end

      # Method 2: Check for custom csp_nonce helper (common in many apps)
      if nonce.blank? && respond_to?(:csp_nonce)
        nonce = csp_nonce
      end

      # Method 3: Try to extract from request environment (where CSP gems often store it)
      if nonce.blank? && defined?(request) && request
        nonce = request.env["action_dispatch.content_security_policy_nonce"] ||
                request.env["secure_headers.content_security_policy_nonce"] ||
                request.env["csp_nonce"]
      end

      # Method 4: Check content_for CSP nonce (some apps set it this way)
      if nonce.blank? && respond_to?(:content_for) && content_for?(:csp_nonce)
        nonce = content_for(:csp_nonce)
      end

      # Method 5: Extract from meta tag if present (less efficient but works)
      if nonce.blank? && defined?(content_security_policy_nonce_tag)
        begin
          tag_content = content_security_policy_nonce_tag
          if tag_content && tag_content.include?("nonce-")
            nonce = tag_content.match(/nonce-([^"']+)/)[1] if tag_content.match(/nonce-([^"']+)/)
          end
        rescue
          # Ignore parsing errors
        end
      end

      # Return the nonce or nil (Rails will handle CSP properly with nil)
      nonce.presence
    end
  end
end
