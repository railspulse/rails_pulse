require "test_helper"

module RailsPulse
  module Cloud
    class PathPrefixTest < ActiveSupport::TestCase
      # Structure Tests

      # The examples in the sync contract's "Rule: unmatched paths".
      {
        "/wp-login.php" => "/wp-login.php",
        "/wp-admin/setup.php" => "/wp-admin/*",
        "/.env" => "/.env",
        "/api/v2/orders/481" => "/api/*",
        "/users/jane.doe@example.com" => "/users/*",
        "/invite/8f3a9c1e2b7d" => "/invite/*",
        "/8f3a9c1e2b7d" => "/*"
      }.each do |stored, sent|
        test "sends #{stored} as #{sent}" do
          assert_equal sent, PathPrefix.for(stored)
        end
      end

      # Calculation Tests

      test "a first segment with a run of four digits is an identifier" do
        assert_equal "/*", PathPrefix.for("/order-12345/receipt")
        assert_equal "/v123/*", PathPrefix.for("/v123/status")
      end

      test "a UUID first segment is an identifier" do
        assert_equal "/*", PathPrefix.for("/0192f0c4-7b1e-7a3c-9d2e-5f6a8b9c0d1e")
      end

      test "an encoded email address is an identifier" do
        assert_equal "/*", PathPrefix.for("/jane%40example.com")
      end

      test "a first segment over 40 characters is not kept" do
        assert_equal "/*", PathPrefix.for("/#{'x' * 41}")
        assert_equal "/#{'x' * 40}", PathPrefix.for("/#{'x' * 40}")
      end

      test "a first segment with characters outside the allowed set is not kept" do
        assert_equal "/*", PathPrefix.for("/:id/edit")
        assert_equal "/*", PathPrefix.for("/caf%C3%A9")
      end

      test "a short hexadecimal word is kept" do
        assert_equal "/cafe/*", PathPrefix.for("/cafe/menu")
      end

      # Edge Cases

      test "the root path is sent as it is" do
        assert_equal "/", PathPrefix.for("/")
      end

      test "a trailing slash counts as something after the first segment" do
        assert_equal "/wp-admin/*", PathPrefix.for("/wp-admin/")
      end

      test "an empty or nil path becomes the catch-all prefix" do
        assert_equal "/*", PathPrefix.for("")
        assert_equal "/*", PathPrefix.for(nil)
      end

      test "safe_segment? refuses anything that is not a string" do
        assert_not PathPrefix.safe_segment?(nil)
        assert_not PathPrefix.safe_segment?(42)
      end
    end
  end
end
