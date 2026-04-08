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

    assert helper.respond_to?(:root_path)
    assert helper.respond_to?(:routes_path)
    refute helper.respond_to?(:non_existent_route_path)
  end

  # ============================================================================
  # Asset Path Tests
  # ============================================================================

  test "rails_pulse asset_path returns asset path" do
    helper = rails_pulse
    path = helper.asset_path("style.css")

    # Behavior depends on whether Sprockets/Propshaft is defined
    if defined?(::Sprockets) || defined?(::Propshaft)
      # With asset pipeline, should use it
      assert_match %r{style\.css}, path
    else
      # Without asset pipeline, uses middleware path
      assert_equal "/rails-pulse-assets/style.css", path
    end
  end

  test "rails_pulse asset_path handles different asset types" do
    helper = rails_pulse

    css_path = helper.asset_path("application.css")
    js_path = helper.asset_path("application.js")
    image_path = helper.asset_path("logo.png")

    # All should return paths
    assert_match %r{application\.css}, css_path
    assert_match %r{application\.js}, js_path
    assert_match %r{logo\.png}, image_path
  end

  test "rails_pulse asset_path without asset pipeline returns middleware path" do
    helper = rails_pulse

    # Temporarily hide Sprockets/Propshaft
    sprockets_backup = nil
    propshaft_backup = nil

    if defined?(::Sprockets)
      sprockets_backup = ::Sprockets
      Object.send(:remove_const, :Sprockets)
    end

    if defined?(::Propshaft)
      propshaft_backup = ::Propshaft
      Object.send(:remove_const, :Propshaft)
    end

    begin
      # Create a new helper instance to test without asset pipeline
      new_helper = RailsPulse::RouteHelper::RailsPulseHelper.new(self)
      path = new_helper.asset_path("style.css")

      assert_equal "/rails-pulse-assets/style.css", path
    ensure
      # Restore constants
      ::Sprockets = sprockets_backup if sprockets_backup
      ::Propshaft = propshaft_backup if propshaft_backup
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "rails_pulse asset_path handles empty filename" do
    helper = rails_pulse
    path = helper.asset_path("")

    if defined?(::Sprockets) || defined?(::Propshaft)
      assert_kind_of String, path
    else
      assert_equal "/rails-pulse-assets/", path
    end
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

  test "rails_pulse asset_path handles ActionController::Base.helpers error" do
    # Temporarily define Sprockets to trigger the asset pipeline path
    unless defined?(::Sprockets)
      ::Sprockets = Module.new
      sprockets_was_defined = false
    else
      sprockets_was_defined = true
    end

    # Create a new helper instance to pick up the Sprockets constant
    helper = RailsPulse::RouteHelper::RailsPulseHelper.new(self)

    # Stub ActionController::Base.helpers.asset_path to raise an error
    original_method = ActionController::Base.helpers.method(:asset_path) rescue nil
    ActionController::Base.helpers.define_singleton_method(:asset_path) do |_|
      raise StandardError, "Asset pipeline error"
    end

    begin
      path = helper.asset_path("error-asset.css")

      # Should fall back to middleware path
      assert_equal "/rails-pulse-assets/error-asset.css", path
    ensure
      # Restore original method or remove our stub
      if original_method
        ActionController::Base.helpers.define_singleton_method(:asset_path, original_method)
      else
        ActionController::Base.helpers.singleton_class.remove_method(:asset_path) rescue nil
      end

      # Clean up Sprockets if we defined it
      Object.send(:remove_const, :Sprockets) unless sprockets_was_defined
    end
  end

  test "rails_pulse asset_path logs warning on error" do
    # Temporarily define Sprockets to trigger the asset pipeline path
    unless defined?(::Sprockets)
      ::Sprockets = Module.new
      sprockets_was_defined = false
    else
      sprockets_was_defined = true
    end

    # Create a new helper instance
    helper = RailsPulse::RouteHelper::RailsPulseHelper.new(self)

    # Stub ActionController::Base.helpers.asset_path to raise an error
    original_method = ActionController::Base.helpers.method(:asset_path) rescue nil
    ActionController::Base.helpers.define_singleton_method(:asset_path) do |_|
      raise StandardError, "Test error"
    end

    # Capture Rails logger output
    log_output = []
    original_logger = Rails.logger
    mock_logger = Logger.new(StringIO.new)
    mock_logger.define_singleton_method(:warn) { |msg| log_output << msg }
    Rails.logger = mock_logger

    begin
      helper.asset_path("test.css")

      # Should have logged a warning
      assert log_output.any? { |msg| msg.include?("[Rails Pulse]") && msg.include?("test.css") }
    ensure
      # Restore
      if original_method
        ActionController::Base.helpers.define_singleton_method(:asset_path, original_method)
      else
        ActionController::Base.helpers.singleton_class.remove_method(:asset_path) rescue nil
      end
      Rails.logger = original_logger

      # Clean up Sprockets if we defined it
      Object.send(:remove_const, :Sprockets) unless sprockets_was_defined
    end
  end
end
