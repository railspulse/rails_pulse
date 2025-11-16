module RailsPulse
  module ApplicationHelper
    include BreadcrumbsHelper
    include ChartHelper
    include FormattingHelper
    include StatusHelper
    include TableHelper
    include FormHelper
    include TagsHelper

    # Include Pagy frontend helpers for Pagy 8.x compatibility
    # Pagy 43+ doesn't need this, but it doesn't hurt to include it
    include Pagy::Frontend if defined?(Pagy::Frontend)

    # Replacement for lucide_icon helper that works with pre-compiled assets
    # Outputs a custom element that will be hydrated by Stimulus
    def rails_pulse_icon(name, options = {})
      width = options[:width] || options["width"] || 24
      height = options[:height] || options["height"] || 24
      css_class = options[:class] || options["class"] || ""
      custom_style = options[:style] || options["style"]

      # Normalize numeric width/height values into px for layout stability
      width_css = normalize_dimension(width)
      height_css = normalize_dimension(height)

      default_style = [
        "display:inline-flex",
        "align-items:center",
        "justify-content:center",
        "width:#{width_css}",
        "height:#{height_css}",
        "flex-shrink:0"
      ].join(";")

      style_attribute = [ default_style, custom_style ].compact.join(";")

      # Additional HTML attributes
      attrs = options.except(:width, :height, :class, :style, "width", "height", "class", "style")

      content_tag("rails-pulse-icon",
        "",
        data: {
          controller: "rails-pulse--icon",
          'rails-pulse--icon-name-value': name,
          'rails-pulse--icon-width-value': width,
          'rails-pulse--icon-height-value': height
        },
        class: css_class,
        style: style_attribute,
        **attrs
      )
    end

    # Backward compatibility alias - can be removed after migration
    alias_method :lucide_icon, :rails_pulse_icon

    def normalize_dimension(value)
      string = value.to_s
      return string if string.empty?

      if string.match?(/[a-z%]+\z/i)
        string
      else
        number = Float(string)
        formatted = number == number.to_i ? number.to_i.to_s : number.to_s
        "#{formatted}px"
      end
    end

    private :normalize_dimension
    # Get items per page from Pagy instance (compatible with Pagy 8.x and 43+)
    def pagy_items(pagy)
      # Pagy 43+ uses options[:items] or has a limit method
      if pagy.respond_to?(:options) && pagy.options.is_a?(Hash)
        pagy.options[:items]
      # Pagy 8.x uses vars[:items]
      elsif pagy.respond_to?(:vars)
        pagy.vars[:items]
      # Fallback
      else
        pagy.limit || 10
      end
    end

    # Get page URL from Pagy instance (compatible with Pagy 8.x and 43+)
    def pagy_page_url(pagy, page_number)
      # Pagy 43+ has page_url method
      if pagy.respond_to?(:page_url)
        pagy.page_url(page_number)
      # Pagy 8.x requires using pagy_url_for helper
      else
        pagy_url_for(pagy, page_number)
      end
    end

    # Get previous page number (compatible with Pagy 8.x and 43+)
    def pagy_previous(pagy)
      # Pagy 43+ uses 'previous'
      if pagy.respond_to?(:previous)
        pagy.previous
      # Pagy 8.x uses 'prev'
      elsif pagy.respond_to?(:prev)
        pagy.prev
      else
        nil
      end
    end

    # Get next page number (compatible with Pagy 8.x and 43+)
    def pagy_next(pagy)
      pagy.respond_to?(:next) ? pagy.next : nil
    end

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
