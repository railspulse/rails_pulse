require "test_helper"

module RailsPulse
  class RoutePathNormalizerTest < ActiveSupport::TestCase
    # Happy Path Tests

    test "normalizes numeric id segment" do
      assert_equal "/users/:id", normalize("/users/42", { id: "42" })
    end

    test "normalizes slug-based id segment" do
      assert_equal "/clients/:id", normalize("/clients/acme-corp", { id: "acme-corp" })
    end

    test "normalizes uuid-style param with custom param name" do
      assert_equal "/submissions/:uuid", normalize("/submissions/SLKe-2342-234-23423", { uuid: "SLKe-2342-234-23423" })
    end

    test "normalizes nested resource with distinct param names" do
      assert_equal "/users/:user_id/posts/:id",
        normalize("/users/42/posts/7", { user_id: "42", id: "7" })
    end

    test "normalizes deeply nested slugs matching the plan example" do
      assert_equal "/connect/partners/:client_id/submissions/:uuid",
        normalize(
          "/connect/partners/some-client-slug/submissions/SLKe-2342-234-23423",
          { client_id: "some-client-slug", uuid: "SLKe-2342-234-23423" }
        )
    end

    # Format Extension Tests

    test "normalizes segment with format extension" do
      assert_equal "/users/:id.json",
        normalize("/users/42.json", { id: "42", format: "json" })
    end

    test "does not parameterize the format extension itself" do
      result = normalize("/users/42.json", { id: "42", format: "json" })
      refute result.include?(":format"), "format should not appear as a param segment"
    end

    # Static Path Tests

    test "returns path unchanged when no route params" do
      assert_equal "/about", normalize("/about", { controller: "pages", action: "about" })
    end

    test "returns path unchanged for versioned api path with no params" do
      assert_equal "/api/v2/status", normalize("/api/v2/status", { controller: "api/status", action: "index" })
    end

    test "returns path unchanged when path_params is empty hash" do
      assert_equal "/users/42", normalize("/users/42", {})
    end

    # Edge Case Tests

    test "returns nil when path is nil" do
      assert_nil normalize(nil, { id: "42" })
    end

    test "returns empty string when path is empty" do
      assert_equal "", normalize("", { id: "42" })
    end

    test "returns path unchanged when path_params is nil" do
      assert_equal "/users/42", normalize("/users/42", nil)
    end

    test "safe fallback for ambiguous duplicate param values" do
      # Both user_id and id are "42" — cannot safely determine which segment is which
      result = normalize("/users/42/similar/42", { user_id: "42", id: "42" })
      assert_equal "/users/42/similar/42", result
    end

    test "skips controller, action, and format keys" do
      result = normalize("/search", { controller: "home", action: "search" })
      assert_equal "/search", result
      refute result.include?(":controller")
      refute result.include?(":action")
    end

    test "class method delegates to instance" do
      class_result = RailsPulse::RoutePathNormalizer.normalize("/posts/5", { id: "5" })
      instance_result = RailsPulse::RoutePathNormalizer.new("/posts/5", { id: "5" }).normalize
      assert_equal "/posts/:id", class_result
      assert_equal class_result, instance_result
    end

    test "is stateless across multiple calls" do
      3.times do
        assert_equal "/posts/:id",
          RailsPulse::RoutePathNormalizer.normalize("/posts/99", { id: "99" })
      end
    end

    private

    def normalize(path, params)
      RailsPulse::RoutePathNormalizer.normalize(path, params)
    end
  end
end
