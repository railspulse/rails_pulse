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

    # Behavior depends on whether Sprockets/Propshaft is defined
    if defined?(::Sprockets) || defined?(::Propshaft)
      # With asset pipeline, tries to use it
      assert_match %r{style\.css}, path
    else
      # Without asset pipeline, uses middleware path
      assert_equal "/rails-pulse-assets/style.css", path
    end

    # It should respond to known routes in engine routes
    assert_respond_to helper, :root_path
  end

  test "rails_pulse_csp_nonce returns nil by default" do
    assert_nil rails_pulse_csp_nonce
  end

  # humanize_time_range Tests

  test "humanize_time_range converts :last_day to 'last 24 hours'" do
    assert_equal "last 24 hours", humanize_time_range(:last_day)
  end

  test "humanize_time_range converts :last_week to 'last week'" do
    assert_equal "last week", humanize_time_range(:last_week)
  end

  test "humanize_time_range converts :last_two_weeks to 'last 2 weeks'" do
    assert_equal "last 2 weeks", humanize_time_range(:last_two_weeks)
  end

  test "humanize_time_range converts :last_month to 'last month'" do
    assert_equal "last month", humanize_time_range(:last_month)
  end

  test "humanize_time_range converts :last_24_hours to 'last 24 hours'" do
    assert_equal "last 24 hours", humanize_time_range(:last_24_hours)
  end

  test "humanize_time_range converts :last_7_days to 'last 7 days'" do
    assert_equal "last 7 days", humanize_time_range(:last_7_days)
  end

  test "humanize_time_range converts :last_14_days to 'last 14 days'" do
    assert_equal "last 14 days", humanize_time_range(:last_14_days)
  end

  test "humanize_time_range converts :last_30_days to 'last 30 days'" do
    assert_equal "last 30 days", humanize_time_range(:last_30_days)
  end

  test "humanize_time_range converts :custom to 'custom range'" do
    assert_equal "custom range", humanize_time_range(:custom)
  end

  test "humanize_time_range accepts string symbols" do
    assert_equal "last week", humanize_time_range("last_week")
  end

  test "humanize_time_range handles unknown symbols with humanized fallback" do
    assert_equal "some other range", humanize_time_range(:some_other_range)
  end
end
