module RailsPulse
  module IconHelper
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

    private

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
  end
end
