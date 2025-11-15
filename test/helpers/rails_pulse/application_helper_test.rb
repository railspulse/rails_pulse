require "test_helper"

class RailsPulse::ApplicationHelperTest < ActionView::TestCase
  include RailsPulse::ApplicationHelper

  test "rails_pulse_icon renders a rails-pulse-icon element with defaults" do
    html = rails_pulse_icon("alert")

    assert_match(/<rails-pulse-icon/, html)
    assert_includes html, "data-controller=\"rails-pulse--icon\""
    assert_includes html, "rails-pulse--icon-name-value=\"alert\""
    assert_includes html, "rails-pulse--icon-width-value=\"24\""
    assert_includes html, "rails-pulse--icon-height-value=\"24\""
    assert_includes html, "style=\"display:inline-flex;align-items:center;justify-content:center;width:24px;height:24px;flex-shrink:0\""
  end

  test "rails_pulse_icon applies custom width, height and class" do
    html = rails_pulse_icon("alert", width: 32, height: 32, class: "my-class")

    assert_includes html, "rails-pulse--icon-width-value=\"32\""
    assert_includes html, "rails-pulse--icon-height-value=\"32\""
    assert_includes html, "class=\"my-class\""
    assert_includes html, "width:32px;height:32px"
  end

  test "rails_pulse_icon merges custom style with default dimensions" do
    html = rails_pulse_icon("alert", style: "margin-left:4px")

    assert_includes html, "flex-shrink:0;margin-left:4px"
  end

  test "rails_pulse_icon passes through extra attributes" do
    html = rails_pulse_icon("alert", id: "icon-1", "data-test": "value")

    assert_includes html, "id=\"icon-1\""
    assert_includes html, "data-test=\"value\""
  end

  test "lucide_icon is an alias for rails_pulse_icon" do
    html1 = rails_pulse_icon("alert")
    html2 = lucide_icon("alert")

    assert_equal html1, html2
  end

  test "rails_pulse returns a RailsPulseHelper with route delegation" do
    helper = rails_pulse

    assert_kind_of RailsPulse::ApplicationHelper::RailsPulseHelper, helper

    # The helper should respond to asset_path
    path = helper.asset_path("style.css")

    assert_equal "/rails-pulse-assets/style.css", path

    # It should respond to known routes in engine routes
    assert_respond_to helper, :root_path
  end

  test "rails_pulse_csp_nonce returns nil by default" do
    assert_nil rails_pulse_csp_nonce
  end
end
