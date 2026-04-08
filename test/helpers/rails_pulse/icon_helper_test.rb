require "test_helper"

class RailsPulse::IconHelperTest < ActionView::TestCase
  include RailsPulse::IconHelper

  # ============================================================================
  # Basic Rendering Tests
  # ============================================================================

  test "rails_pulse_icon renders a rails-pulse-icon element with defaults" do
    html = rails_pulse_icon("alert")

    assert_match(/<rails-pulse-icon/, html)
    assert_includes html, "data-controller=\"rails-pulse--icon\""
    assert_includes html, "rails-pulse--icon-name-value=\"alert\""
    assert_includes html, "rails-pulse--icon-width-value=\"24\""
    assert_includes html, "rails-pulse--icon-height-value=\"24\""
    assert_includes html, "style=\"display:inline-flex;align-items:center;justify-content:center;width:24px;height:24px;flex-shrink:0\""
  end

  test "rails_pulse_icon renders with correct data attributes" do
    html = rails_pulse_icon("check")

    assert_includes html, "data-controller=\"rails-pulse--icon\""
    assert_includes html, "data-rails-pulse--icon-name-value=\"check\""
  end

  # ============================================================================
  # Options & Variations
  # ============================================================================

  test "rails_pulse_icon applies custom width and height as integers" do
    html = rails_pulse_icon("alert", width: 32, height: 32)

    assert_includes html, "rails-pulse--icon-width-value=\"32\""
    assert_includes html, "rails-pulse--icon-height-value=\"32\""
    assert_includes html, "width:32px;height:32px"
  end

  test "rails_pulse_icon applies custom width and height as strings" do
    html = rails_pulse_icon("alert", "width" => "48", "height" => "48")

    assert_includes html, "rails-pulse--icon-width-value=\"48\""
    assert_includes html, "rails-pulse--icon-height-value=\"48\""
    assert_includes html, "width:48px;height:48px"
  end

  test "rails_pulse_icon applies custom CSS class" do
    html = rails_pulse_icon("alert", class: "my-custom-class")

    assert_includes html, "class=\"my-custom-class\""
  end

  test "rails_pulse_icon applies multiple CSS classes" do
    html = rails_pulse_icon("alert", class: "icon-large text-red-500")

    assert_includes html, "class=\"icon-large text-red-500\""
  end

  test "rails_pulse_icon merges custom style with default styles" do
    html = rails_pulse_icon("alert", style: "margin-left:4px")

    assert_includes html, "display:inline-flex"
    assert_includes html, "margin-left:4px"
  end

  test "rails_pulse_icon handles dimensions with units" do
    html = rails_pulse_icon("alert", width: "2rem", height: "2rem")

    assert_includes html, "width:2rem"
    assert_includes html, "height:2rem"
  end

  test "rails_pulse_icon handles percentage dimensions" do
    html = rails_pulse_icon("alert", width: "100%", height: "100%")

    assert_includes html, "width:100%"
    assert_includes html, "height:100%"
  end

  test "rails_pulse_icon passes through extra HTML attributes" do
    html = rails_pulse_icon("alert", id: "icon-1", "data-test": "value", title: "Alert Icon")

    assert_includes html, "id=\"icon-1\""
    assert_includes html, "data-test=\"value\""
    assert_includes html, "title=\"Alert Icon\""
  end

  test "rails_pulse_icon does not pass dimension options as HTML attributes" do
    html = rails_pulse_icon("alert", width: 32, height: 32, class: "icon")

    # Dimensions should be in data attributes and styles, not as HTML attributes
    refute_includes html, "width=\"32\""
    refute_includes html, "height=\"32\""
  end

  # ============================================================================
  # Alias Tests
  # ============================================================================

  test "lucide_icon is an alias for rails_pulse_icon" do
    html1 = rails_pulse_icon("alert")
    html2 = lucide_icon("alert")

    assert_equal html1, html2
  end

  test "lucide_icon accepts the same options as rails_pulse_icon" do
    html1 = rails_pulse_icon("check", width: 32, class: "icon-test")
    html2 = lucide_icon("check", width: 32, class: "icon-test")

    assert_equal html1, html2
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "rails_pulse_icon handles empty icon name" do
    html = rails_pulse_icon("")

    assert_includes html, "rails-pulse--icon-name-value=\"\""
  end

  test "rails_pulse_icon handles icon name with special characters" do
    html = rails_pulse_icon("alert-triangle")

    assert_includes html, "rails-pulse--icon-name-value=\"alert-triangle\""
  end

  test "rails_pulse_icon handles zero dimensions" do
    html = rails_pulse_icon("alert", width: 0, height: 0)

    assert_includes html, "width:0px"
    assert_includes html, "height:0px"
  end

  test "rails_pulse_icon handles float dimensions" do
    html = rails_pulse_icon("alert", width: 16.5, height: 16.5)

    assert_includes html, "width:16.5px"
    assert_includes html, "height:16.5px"
  end

  test "rails_pulse_icon handles empty options hash" do
    html = rails_pulse_icon("alert", {})

    assert_includes html, "rails-pulse--icon-name-value=\"alert\""
    assert_includes html, "width:24px;height:24px"  # Uses defaults
  end

  test "rails_pulse_icon handles nil class option" do
    html = rails_pulse_icon("alert", class: nil)

    assert_includes html, "class=\"\""
  end

  test "rails_pulse_icon handles empty style option" do
    html = rails_pulse_icon("alert", style: "")

    # Should still have default styles even with empty custom style
    assert_includes html, "display:inline-flex"
  end

  # ============================================================================
  # Private Method Tests (tested indirectly)
  # ============================================================================

  test "normalize_dimension converts integer to px" do
    html = rails_pulse_icon("alert", width: 24)

    assert_includes html, "width:24px"
  end

  test "normalize_dimension converts float to px" do
    html = rails_pulse_icon("alert", width: 24.5)

    assert_includes html, "width:24.5px"
  end

  test "normalize_dimension preserves units" do
    html = rails_pulse_icon("alert", width: "2rem")

    assert_includes html, "width:2rem"
  end

  test "normalize_dimension handles percentage" do
    html = rails_pulse_icon("alert", width: "50%")

    assert_includes html, "width:50%"
  end

  test "normalize_dimension handles empty string" do
    html = rails_pulse_icon("alert", width: "")

    # Empty string should be preserved as-is
    assert_includes html, "rails-pulse-icon"
  end
end
