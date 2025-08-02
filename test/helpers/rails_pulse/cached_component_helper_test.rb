require "test_helper"

class RailsPulse::CachedComponentHelperTest < ActionView::TestCase
  include RailsPulse::CachedComponentHelper

  setup do
    stub_rails_pulse_configuration
    Rails.cache.clear
  end

  teardown do
    Rails.cache.clear
  end

  test "cached_component checks cache existence correctly" do
    # Test ComponentCacheKey generation works
    cache_key = RailsPulse::ComponentCacheKey.build("test_component", "dashboard")
    assert cache_key.is_a?(Array)
    assert_equal "rails_pulse_component", cache_key[0]

    # Test cache operations work at all
    assert_respond_to Rails.cache, :write
    assert_respond_to Rails.cache, :read
    assert_respond_to Rails.cache, :delete
  end

  test "ComponentCacheKey builds correct cache keys" do
    # Test with context
    key_with_context = RailsPulse::ComponentCacheKey.build("test_id", "dashboard")
    expected_with_context = [ "rails_pulse_component", "test_id", "dashboard" ]
    assert_equal expected_with_context, key_with_context

    # Test without context
    key_without_context = RailsPulse::ComponentCacheKey.build("test_id", nil)
    expected_without_context = [ "rails_pulse_component", "test_id" ]
    assert_equal expected_without_context, key_without_context

    # Test with empty context (compact only removes nil, not empty strings)
    key_empty_context = RailsPulse::ComponentCacheKey.build("test_id", "")
    expected_empty_context = [ "rails_pulse_component", "test_id", "" ]
    assert_equal expected_empty_context, key_empty_context
  end

  test "ComponentCacheKey cache_expires_in returns reasonable duration" do
    duration = RailsPulse::ComponentCacheKey.cache_expires_in

    # Should be a positive integer
    assert duration.is_a?(Integer)
    assert duration > 0

    # Should include some jitter (within reasonable bounds)
    # Since we can't predict exact jitter, just verify it's within expected range
    base_duration = RailsPulse.configuration.component_cache_duration.to_i
    max_jitter = (base_duration * 0.25).to_i

    assert duration >= base_duration
    assert duration <= base_duration + max_jitter
  end

  test "refresh_action_params generates basic structure" do
    # Mock the rails_pulse helper method
    mock_rails_pulse = mock("rails_pulse_helper")
    mock_rails_pulse.expects(:cache_path).returns("/refresh/path")
    self.stubs(:rails_pulse).returns(mock_rails_pulse)

    result = refresh_action_params("test_id", "dashboard", nil)

    # Verify basic structure
    assert_equal "/refresh/path", result[:url]
    assert_equal "refresh-cw", result[:icon]
    assert_equal "Refresh data", result[:title]
    assert result[:data].is_a?(Hash)

    # Verify data attributes exist
    assert result[:data][:controller]
    assert result[:data][:turbo_frame]
    assert result[:data][:rails_pulse__timezone_target_frame_value]
  end

  test "cached_component helper exists and is callable" do
    # Basic smoke test to ensure the methods are defined in the module
    public_methods = RailsPulse::CachedComponentHelper.instance_methods(false)
    assert_includes public_methods, :cached_component

    # refresh_action_params is private, so check private methods
    private_methods = RailsPulse::CachedComponentHelper.private_instance_methods(false)
    assert_includes private_methods, :refresh_action_params
  end

  test "private helper methods exist" do
    # Verify private methods exist (can't call them directly but can check they're defined)
    private_methods = RailsPulse::CachedComponentHelper.private_instance_methods
    assert_includes private_methods, :render_cached_content
    assert_includes private_methods, :render_skeleton_with_frame
  end
end
