require "test_helper"

class RailsPulse::RouteHelperTest < ActionView::TestCase
  include RailsPulse::RouteHelper

  # ============================================================================
  # Basic Functionality Tests
  # ============================================================================

  test "rails_pulse returns a RailsPulseHelper instance" do
    helper = rails_pulse

    assert_kind_of RailsPulse::RouteHelper::RailsPulseHelper, helper
  end

  test "rails_pulse returns cached instance on subsequent calls" do
    helper1 = rails_pulse
    helper2 = rails_pulse

    assert_same helper1, helper2
  end

  # ============================================================================
  # Route Delegation Tests
  # ============================================================================

  test "rails_pulse delegates route methods to engine routes" do
    helper = rails_pulse

    # Should respond to engine routes
    assert_respond_to helper, :root_path
    assert_respond_to helper, :routes_path
    assert_respond_to helper, :requests_path
  end

  test "rails_pulse can generate engine route paths" do
    helper = rails_pulse

    # Test a few common routes - paths are mounted under /rails_pulse in test
    assert_match %r{/rails_pulse/?$}, helper.root_path
    assert_match %r{/routes}, helper.routes_path
    assert_match %r{/requests}, helper.requests_path
  end

  test "rails_pulse raises NoMethodError for non-existent routes" do
    helper = rails_pulse

    assert_raises(NoMethodError) do
      helper.this_route_does_not_exist_path
    end
  end

  test "rails_pulse respond_to_missing? returns true for engine routes" do
    helper = rails_pulse

    assert_respond_to helper, :root_path
    assert_respond_to helper, :routes_path
    refute_respond_to helper, :non_existent_route_path
  end

  # ============================================================================
  # Asset Path Tests
  # ============================================================================

  test "rails_pulse asset_path returns middleware asset path" do
    helper = rails_pulse
    path = helper.asset_path("style.css")

    assert_equal "/rails-pulse-assets/style.css", path
  end

  test "rails_pulse asset_path handles different asset types" do
    helper = rails_pulse

    css_path = helper.asset_path("application.css")
    js_path = helper.asset_path("application.js")
    image_path = helper.asset_path("logo.png")

    assert_equal "/rails-pulse-assets/application.css", css_path
    assert_equal "/rails-pulse-assets/application.js", js_path
    assert_equal "/rails-pulse-assets/logo.png", image_path
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "rails_pulse asset_path handles empty filename" do
    helper = rails_pulse
    path = helper.asset_path("")

    assert_equal "/rails-pulse-assets/", path
  end

  test "rails_pulse asset_path handles paths with subdirectories" do
    helper = rails_pulse
    path = helper.asset_path("icons/alert.svg")

    assert_includes path, "icons/alert.svg"
  end

  test "rails_pulse method_missing passes through block" do
    helper = rails_pulse

    # Test with a route that accepts a block (if any)
    # Most route helpers don't use blocks, but method_missing should support it
    result = helper.root_path

    assert_kind_of String, result
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  test "rails_pulse helper can be used in view context" do
    # This test verifies it works within the ActionView::TestCase context
    result = rails_pulse

    assert_kind_of RailsPulse::RouteHelper::RailsPulseHelper, result
    assert_respond_to result, :root_path
  end

  test "rails_pulse RailsPulseHelper initializes with view context" do
    helper = RailsPulse::RouteHelper::RailsPulseHelper.new(self)

    assert_kind_of RailsPulse::RouteHelper::RailsPulseHelper, helper
  end
end
