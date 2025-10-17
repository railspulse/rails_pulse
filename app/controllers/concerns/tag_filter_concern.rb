module TagFilterConcern
  extend ActiveSupport::Concern

  private

  # Apply tag filters to a query
  # Excludes records that have ANY of the disabled tags
  def apply_tag_filters(query)
    disabled_tags = session_disabled_tags
    return query if disabled_tags.empty?

    disabled_tags.reduce(query) do |q, tag|
      q.without_tag(tag)
    end
  end
end
