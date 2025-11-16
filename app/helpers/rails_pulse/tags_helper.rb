module RailsPulse
  module TagsHelper
    # Render a single tag badge
    # Options:
    # - variant: :default (no class), :secondary, :positive
    # - removable: boolean - whether to include a remove button
    # - taggable_type: string - type of taggable object (for remove button)
    # - taggable_id: integer - id of taggable object (for remove button)
    def render_tag_badge(tag, variant: :default, removable: false, taggable_type: nil, taggable_id: nil)
      badge_class = case variant
      when :secondary
        "badge badge--secondary font-normal"
      when :positive
        "badge badge--positive font-normal"
      else
        "badge font-normal"
      end

      if removable && taggable_type && taggable_id
        # For removable tags, render the full structure with button_to
        content_tag(:span, class: badge_class) do
          concat tag.humanize
          concat " "
          concat(
            button_to(
              remove_tag_path(taggable_type, taggable_id, tag: tag),
              method: :delete,
              class: "tag-remove",
              data: { turbo_frame: "_top" }
            ) do
              content_tag(:span, "×", "aria-hidden": "true")
            end
          )
        end
      else
        # For non-removable tags, just render the badge
        content_tag(:span, tag, class: badge_class)
      end
    end

    # Display tags as badge elements
    # Accepts:
    # - Taggable objects (with tag_list method)
    # - Raw JSON strings from aggregated queries
    # - Arrays of tags
    def display_tag_badges(tags)
      tag_array = case tags
      when String
        # Parse JSON string from database
        begin
          JSON.parse(tags)
        rescue JSON::ParserError
          []
        end
      when Array
        tags
      else
        # Handle Taggable objects
        tags.respond_to?(:tag_list) ? tags.tag_list : []
      end

      return content_tag(:span, "-", class: "text-subtle") if tag_array.empty?

      safe_join(tag_array.map { |tag| content_tag(:div, tag.humanize, class: "badge") }, " ")
    end
  end
end
