require "test_helper"
require "ostruct"

class RailsPulse::CspHelperTest < ActionView::TestCase
  include RailsPulse::CspHelper

  # ============================================================================
  # Basic Functionality Tests
  # ============================================================================

  test "rails_pulse_csp_nonce returns nil when no CSP nonce is available" do
    # In test environment with no CSP configured, should return nil
    result = rails_pulse_csp_nonce

    assert_nil result
  end

  test "rails_pulse_csp_nonce is defined" do
    assert_respond_to self, :rails_pulse_csp_nonce
  end

  # ============================================================================
  # Method Detection Tests
  # ============================================================================

  test "rails_pulse_csp_nonce tries multiple detection methods" do
    # Test that it looks for content_security_policy_nonce first
    nonce = "test-nonce-#{SecureRandom.hex(8)}"

    # Define the Rails 6+ helper method
    define_singleton_method(:content_security_policy_nonce) { nonce }

    result = rails_pulse_csp_nonce

    assert_equal nonce, result

    # Clean up
    singleton_class.remove_method(:content_security_policy_nonce)
  end

  test "rails_pulse_csp_nonce falls back to custom csp_nonce helper" do
    nonce = "test-nonce-#{SecureRandom.hex(8)}"

    # Define custom csp_nonce method (when content_security_policy_nonce doesn't exist)
    define_singleton_method(:csp_nonce) { nonce }

    result = rails_pulse_csp_nonce

    assert_equal nonce, result

    # Clean up
    singleton_class.remove_method(:csp_nonce)
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "rails_pulse_csp_nonce filters out blank nonces" do
    # Define a method that returns empty string
    define_singleton_method(:content_security_policy_nonce) { "" }

    result = rails_pulse_csp_nonce

    # Empty strings should be treated as nil
    assert_nil result

    # Clean up
    singleton_class.remove_method(:content_security_policy_nonce)
  end

  test "rails_pulse_csp_nonce filters out whitespace-only nonces" do
    # Define a method that returns whitespace
    define_singleton_method(:content_security_policy_nonce) { "   " }

    result = rails_pulse_csp_nonce

    # Whitespace should be treated as nil
    assert_nil result

    # Clean up
    singleton_class.remove_method(:content_security_policy_nonce)
  end

  test "rails_pulse_csp_nonce preserves valid nonce values" do
    nonce = "valid-nonce-123"

    define_singleton_method(:content_security_policy_nonce) { nonce }

    result = rails_pulse_csp_nonce

    assert_equal nonce, result

    # Clean up
    singleton_class.remove_method(:content_security_policy_nonce)
  end

  test "rails_pulse_csp_nonce handles content_for pattern" do
    nonce = "content-for-nonce"

    # Simulate content_for(:csp_nonce) being set
    define_singleton_method(:content_for?) { |key| key == :csp_nonce }
    define_singleton_method(:content_for) { |key| key == :csp_nonce ? nonce : nil }

    result = rails_pulse_csp_nonce

    assert_equal nonce, result

    # Clean up
    singleton_class.remove_method(:content_for?)
    singleton_class.remove_method(:content_for)
  end

  # ============================================================================
  # Method Priority Tests
  # ============================================================================

  test "rails_pulse_csp_nonce prefers content_security_policy_nonce over others" do
    nonce1 = "preferred-nonce"
    nonce2 = "fallback-nonce"

    # Define both methods
    define_singleton_method(:content_security_policy_nonce) { nonce1 }
    define_singleton_method(:csp_nonce) { nonce2 }

    result = rails_pulse_csp_nonce

    # Should use content_security_policy_nonce (first method)
    assert_equal nonce1, result

    # Clean up
    singleton_class.remove_method(:content_security_policy_nonce)
    singleton_class.remove_method(:csp_nonce)
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  test "rails_pulse_csp_nonce works in ActionView test context" do
    # Verify it can be called in a view helper context
    assert_nothing_raised do
      rails_pulse_csp_nonce
    end
  end

  test "rails_pulse_csp_nonce checks request environment" do
    nonce = "env-nonce-123"

    # Create a mock request with CSP nonce in environment
    mock_request = OpenStruct.new(
      env: {
        "action_dispatch.content_security_policy_nonce" => nonce
      }
    )

    # Define request method
    define_singleton_method(:request) { mock_request }

    result = rails_pulse_csp_nonce

    assert_equal nonce, result

    # Clean up
    singleton_class.remove_method(:request)
  end

  test "rails_pulse_csp_nonce checks secure_headers env key" do
    nonce = "secure-headers-nonce"

    mock_request = OpenStruct.new(
      env: {
        "secure_headers.content_security_policy_nonce" => nonce
      }
    )

    define_singleton_method(:request) { mock_request }

    result = rails_pulse_csp_nonce

    assert_equal nonce, result

    singleton_class.remove_method(:request)
  end

  test "rails_pulse_csp_nonce checks csp_nonce env key" do
    nonce = "env-csp-nonce"

    mock_request = OpenStruct.new(
      env: {
        "csp_nonce" => nonce
      }
    )

    define_singleton_method(:request) { mock_request }

    result = rails_pulse_csp_nonce

    assert_equal nonce, result

    singleton_class.remove_method(:request)
  end

  test "rails_pulse_csp_nonce extracts from meta tag" do
    nonce = "meta-tag-nonce-abc123"

    # Define content_security_policy_nonce_tag method that returns a meta tag
    define_singleton_method(:content_security_policy_nonce_tag) do
      "<meta name=\"csp-nonce\" content=\"nonce-#{nonce}\" />"
    end

    result = rails_pulse_csp_nonce

    assert_equal nonce, result

    singleton_class.remove_method(:content_security_policy_nonce_tag)
  end

  test "rails_pulse_csp_nonce handles meta tag parsing errors gracefully" do
    # Define a method that returns invalid content
    define_singleton_method(:content_security_policy_nonce_tag) do
      "invalid meta tag content"
    end

    # Should not raise an error, should return nil
    result = rails_pulse_csp_nonce

    assert_nil result

    singleton_class.remove_method(:content_security_policy_nonce_tag)
  end

  test "rails_pulse_csp_nonce handles meta tag method raising error" do
    # Define a method that raises an error
    define_singleton_method(:content_security_policy_nonce_tag) do
      raise StandardError, "Meta tag error"
    end

    # Should rescue the error and return nil
    result = rails_pulse_csp_nonce

    assert_nil result

    singleton_class.remove_method(:content_security_policy_nonce_tag)
  end
end
