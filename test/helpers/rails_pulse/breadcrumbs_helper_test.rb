require "test_helper"

class RailsPulse::BreadcrumbsHelperTest < ActionView::TestCase
  include RailsPulse::BreadcrumbsHelper

  # TODO: Test breadcrumbs returns array with Home link for root path
  # TODO: Test breadcrumbs builds path segments after engine mount point
  # TODO: Test breadcrumbs converts numeric segments to resource names using to_breadcrumb
  # TODO: Test breadcrumbs falls back to to_s when to_breadcrumb not available
  # TODO: Test breadcrumbs titleizes non-numeric segments
  # TODO: Test breadcrumbs marks last segment as current
  # TODO: Test breadcrumbs builds correct paths for each segment
  # TODO: Test breadcrumbs handles missing resources gracefully
  # TODO: Test breadcrumbs returns empty array when no segments after mount point
end
