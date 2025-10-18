module TagFilterConcern
  extend ActiveSupport::Concern

  private

  # Apply tag filters to a query
  # Excludes records that have ANY of the disabled tags
  def apply_tag_filters(query)
    disabled_tags = session_disabled_tags
    query = disabled_tags.reduce(query) do |q, tag|
      q.without_tag(tag)
    end

    apply_non_tagged_filter(query)
  end

  # Apply non-tagged filter to a query
  # If show_non_tagged is false, exclude records with no tags
  def apply_non_tagged_filter(query)
    if session[:show_non_tagged] == false
      query.with_tags
    else
      query
    end
  end
end
