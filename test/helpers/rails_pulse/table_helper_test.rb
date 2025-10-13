require "test_helper"

class RailsPulse::TableHelperTest < ActionView::TestCase
  include RailsPulse::TableHelper

  # TODO: Test render_cell_content with simple value
  # TODO: Test render_cell_content with link_to option
  # TODO: Test render_cell_content with link_field for query_id
  # TODO: Test render_cell_content with link_field for route_id
  # TODO: Test render_cell_content formats percentages with + or - prefix
  # TODO: Test render_cell_content formats time fields with "ms" suffix
  # TODO: Test render_cell_content rounds numeric time values
  # TODO: Test cell_highlight_class returns empty string when no highlight
  # TODO: Test cell_highlight_class with trend highlighting (worse/better)
  # TODO: Test cell_highlight_class with percentage_change highlighting (>5% red, <-5% green)
end
