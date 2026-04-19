# SessionFiltersConcern
#
# Provides helper methods for accessing session-based filters and preferences.
# Manages global filters, disabled tags, time range preferences, and tag visibility.
module SessionFiltersConcern
  extend ActiveSupport::Concern

  included do
    before_action :set_show_non_tagged_default
    helper_method :session_global_filters, :session_disabled_tags, :session_time_range_preference
  end

  private

  # Returns the global filters hash from session
  # Always returns a hash, even if session value is invalid
  def session_global_filters
    filters = session[:global_filters]
    filters.is_a?(Hash) ? filters : {}
  end

  # Returns the array of disabled tags from global filters
  def session_disabled_tags
    session_global_filters["disabled_tags"] || []
  end

  # Returns the time range preference from session
  # Can be a symbol/string for presets or a hash for custom ranges
  def session_time_range_preference
    session[:time_range_preference]
  end

  # Set default value for show_non_tagged if not already set
  # Called as a before_action to ensure the value is always present
  def set_show_non_tagged_default
    session[:show_non_tagged] = true if session[:show_non_tagged].nil?
  end
end
