module RailsPulse
  module TagsHelper
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

      safe_join(tag_array.map { |tag| content_tag(:div, tag, class: "badge") }, " ")
    end
  end
end
