require "test_helper"

class RailsPulse::TableHelperTest < ActionView::TestCase
  include RailsPulse::TableHelper
  include RailsPulse::Engine.routes.url_helpers

  # ============================================================================
  # render_cell_content Tests - Basic Values
  # ============================================================================

  test "render_cell_content returns simple string value" do
    row_data = { name: "Test Route" }
    column = { field: :name }

    result = render_cell_content(row_data, column)

    assert_equal "Test Route", result
  end

  test "render_cell_content returns numeric value" do
    row_data = { count: 42 }
    column = { field: :count }

    result = render_cell_content(row_data, column)

    assert_equal 42, result
  end

  test "render_cell_content returns nil value" do
    row_data = { value: nil }
    column = { field: :value }

    result = render_cell_content(row_data, column)

    assert_nil result
  end

  # ============================================================================
  # render_cell_content Tests - Links
  # ============================================================================

  test "render_cell_content with link_to creates link" do
    row_data = { name: "Test", path: "/test/path" }
    column = { field: :name, link_to: :path }

    result = render_cell_content(row_data, column)

    assert_includes result, "Test"
    assert_includes result, "/test/path"
    assert_includes result, "<a"
  end

  test "render_cell_content with link_field for query_id creates query link" do
    row_data = { name: "SELECT * FROM users", query_id: 123 }
    column = { field: :name, link_field: :query_id }

    result = render_cell_content(row_data, column)

    assert_includes result, "SELECT * FROM users"
    assert_includes result, "queries/123"
    assert_includes result, "<a"
  end

  test "render_cell_content with link_field for route_id creates route link" do
    row_data = { path: "/api/users", route_id: 456 }
    column = { field: :path, link_field: :route_id }

    result = render_cell_content(row_data, column)

    assert_includes result, "/api/users"
    assert_includes result, "routes/456"
    assert_includes result, "<a"
  end

  test "render_cell_content with unknown link_field returns plain value" do
    row_data = { name: "Test", other_id: 789 }
    column = { field: :name, link_field: :other_id }

    result = render_cell_content(row_data, column)

    assert_equal "Test", result
  end

  test "render_cell_content with link_to but no path returns plain value" do
    row_data = { name: "Test", path: nil }
    column = { field: :name, link_to: :path }

    result = render_cell_content(row_data, column)

    assert_equal "Test", result
  end

  test "render_cell_content with link_field but no id returns plain value" do
    row_data = { name: "Test", query_id: nil }
    column = { field: :name, link_field: :query_id }

    result = render_cell_content(row_data, column)

    assert_equal "Test", result
  end

  # ============================================================================
  # render_cell_content Tests - Formatting
  # ============================================================================

  test "render_cell_content formats positive percentage with plus sign" do
    row_data = { change: 15.5 }
    column = { field: :change, format: :percentage }

    result = render_cell_content(row_data, column)

    assert_equal "+15.5%", result
  end

  test "render_cell_content formats negative percentage without extra sign" do
    row_data = { change: -10.2 }
    column = { field: :change, format: :percentage }

    result = render_cell_content(row_data, column)

    assert_equal "-10.2%", result
  end

  test "render_cell_content formats zero percentage without sign" do
    row_data = { change: 0 }
    column = { field: :change, format: :percentage }

    result = render_cell_content(row_data, column)

    assert_equal "0%", result
  end

  test "render_cell_content formats time fields with ms suffix" do
    row_data = { response_time: 150.75 }
    column = { field: :response_time }

    result = render_cell_content(row_data, column)

    assert_equal "151 ms", result
  end

  test "render_cell_content rounds time values to integer" do
    row_data = { avg_time: 99.999 }
    column = { field: :avg_time }

    result = render_cell_content(row_data, column)

    assert_equal "100 ms", result
  end

  test "render_cell_content does not format non-numeric time fields" do
    row_data = { response_time: "N/A" }
    column = { field: :response_time }

    result = render_cell_content(row_data, column)

    assert_equal "N/A", result
  end

  test "render_cell_content handles percentage format with non-numeric value" do
    row_data = { change: "N/A" }
    column = { field: :change, format: :percentage }

    result = render_cell_content(row_data, column)

    assert_equal "N/A", result
  end

  test "render_cell_content formats float time value" do
    row_data = { duration_time: 123.456 }
    column = { field: :duration_time }

    result = render_cell_content(row_data, column)

    assert_equal "123 ms", result
  end

  test "render_cell_content formats integer time value" do
    row_data = { exec_time: 500 }
    column = { field: :exec_time }

    result = render_cell_content(row_data, column)

    assert_equal "500 ms", result
  end

  # ============================================================================
  # cell_highlight_class Tests
  # ============================================================================

  test "cell_highlight_class returns empty string when no highlight option" do
    row_data = { value: 100 }
    column = { field: :value }

    result = cell_highlight_class(row_data, column)

    assert_equal "", result
  end

  test "cell_highlight_class with trend worse returns red highlight" do
    row_data = { trend: "worse" }
    column = { field: :value, highlight: :trend }

    result = cell_highlight_class(row_data, column)

    assert_equal "highlight-red", result
  end

  test "cell_highlight_class with trend better returns green highlight" do
    row_data = { trend: "better" }
    column = { field: :value, highlight: :trend }

    result = cell_highlight_class(row_data, column)

    assert_equal "highlight-green", result
  end

  test "cell_highlight_class with trend neutral returns empty string" do
    row_data = { trend: "neutral" }
    column = { field: :value, highlight: :trend }

    result = cell_highlight_class(row_data, column)

    assert_equal "", result
  end

  test "cell_highlight_class with trend nil returns empty string" do
    row_data = { trend: nil }
    column = { field: :value, highlight: :trend }

    result = cell_highlight_class(row_data, column)

    assert_equal "", result
  end

  test "cell_highlight_class with percentage_change above 5 returns red" do
    row_data = { percentage_change: 10.5 }
    column = { field: :value, highlight: :percentage_change }

    result = cell_highlight_class(row_data, column)

    assert_equal "highlight-red", result
  end

  test "cell_highlight_class with percentage_change below -5 returns green" do
    row_data = { percentage_change: -10.5 }
    column = { field: :value, highlight: :percentage_change }

    result = cell_highlight_class(row_data, column)

    assert_equal "highlight-green", result
  end

  test "cell_highlight_class with percentage_change between -5 and 5 returns empty" do
    row_data = { percentage_change: 3.0 }
    column = { field: :value, highlight: :percentage_change }

    result = cell_highlight_class(row_data, column)

    assert_equal "", result
  end

  test "cell_highlight_class with percentage_change exactly 5 returns empty" do
    row_data = { percentage_change: 5.0 }
    column = { field: :value, highlight: :percentage_change }

    result = cell_highlight_class(row_data, column)

    assert_equal "", result
  end

  test "cell_highlight_class with percentage_change exactly -5 returns empty" do
    row_data = { percentage_change: -5.0 }
    column = { field: :value, highlight: :percentage_change }

    result = cell_highlight_class(row_data, column)

    assert_equal "", result
  end

  test "cell_highlight_class with percentage_change nil returns empty" do
    row_data = { percentage_change: nil }
    column = { field: :value, highlight: :percentage_change }

    result = cell_highlight_class(row_data, column)

    assert_equal "", result
  end

  test "cell_highlight_class with unknown highlight type returns empty" do
    row_data = { value: 100 }
    column = { field: :value, highlight: :unknown }

    result = cell_highlight_class(row_data, column)

    assert_equal "", result
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "render_cell_content handles missing field in row_data" do
    row_data = { name: "Test" }
    column = { field: :missing_field }

    result = render_cell_content(row_data, column)

    assert_nil result
  end

  test "cell_highlight_class handles missing trend in row_data" do
    row_data = {}
    column = { field: :value, highlight: :trend }

    result = cell_highlight_class(row_data, column)

    assert_equal "", result
  end

  test "cell_highlight_class handles missing percentage_change in row_data" do
    row_data = {}
    column = { field: :value, highlight: :percentage_change }

    result = cell_highlight_class(row_data, column)

    assert_equal "", result
  end
end
