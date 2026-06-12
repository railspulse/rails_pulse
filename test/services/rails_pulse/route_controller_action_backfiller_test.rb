require "test_helper"

module RailsPulse
  class RouteControllerActionBackfillerTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes, :rails_pulse_requests

    # Backfill Tests

    test "sets controller_action on route with nil value" do
      route = create_route("GET", "/posts/99")

      RailsPulse::RouteControllerActionBackfiller.call

      assert_equal "home#index", route.reload.controller_action
    end

    test "sets controller_action using lowercase controller#action format" do
      route = create_route("GET", "/partners/acme/submissions/abc-123")

      RailsPulse::RouteControllerActionBackfiller.call

      assert_equal "home#index", route.reload.controller_action
    end

    test "does not overwrite existing controller_action" do
      route = create_route("GET", "/posts/99", controller_action: "posts#show")

      RailsPulse::RouteControllerActionBackfiller.call

      assert_equal "posts#show", route.reload.controller_action
    end

    test "leaves unrecognized paths unchanged" do
      route = create_route("GET", "/nonexistent/route/999")

      RailsPulse::RouteControllerActionBackfiller.call

      assert_nil route.reload.controller_action
    end

    # Results Hash Tests

    test "returns accurate updated count" do
      create_route("GET", "/posts/42")

      results = RailsPulse::RouteControllerActionBackfiller.call

      assert_operator results[:updated], :>=, 1
    end

    test "returns accurate skipped count for unrecognized paths" do
      create_route("GET", "/ghost/route/999")

      results = RailsPulse::RouteControllerActionBackfiller.call

      assert_operator results[:skipped], :>=, 1
    end

    test "returns accurate already_set count" do
      create_route("GET", "/posts/42", controller_action: "posts#show")

      results = RailsPulse::RouteControllerActionBackfiller.call

      assert_operator results[:already_set], :>=, 1
    end

    test "results hash has all three keys" do
      results = RailsPulse::RouteControllerActionBackfiller.call

      assert results.key?(:updated)
      assert results.key?(:skipped)
      assert results.key?(:already_set)
    end

    # Idempotency Tests

    test "running twice does not change already-set routes" do
      route = create_route("GET", "/posts/99")
      RailsPulse::RouteControllerActionBackfiller.call
      first_value = route.reload.controller_action

      RailsPulse::RouteControllerActionBackfiller.call

      assert_equal first_value, route.reload.controller_action
    end

    test "second run reports routes as already_set" do
      create_route("GET", "/posts/42")
      RailsPulse::RouteControllerActionBackfiller.call

      results = RailsPulse::RouteControllerActionBackfiller.call

      assert_operator results[:already_set], :>=, 1
      assert_equal 0, results[:updated]
    end

    private

    def create_route(http_method, path, controller_action: nil)
      RailsPulse::Route.create!(http_methods: [ http_method ].to_json, path: path, tags: "[]", controller_action: controller_action)
    end
  end
end
