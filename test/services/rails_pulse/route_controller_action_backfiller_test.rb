require "test_helper"

module RailsPulse
  class RouteControllerActionBackfillerTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes, :rails_pulse_requests

    setup do
      # Establish a clean baseline so per-test result counts are exact.
      @baseline = RailsPulse::RouteControllerActionBackfiller.call
    end

    # Backfill Tests

    test "sets controller_action on route with nil value" do
      route = create_route("GET", "/posts/99")

      results = call_backfiller

      assert_equal "home#index", route.reload.controller_action
      assert_equal @baseline[:updated] + 1, results[:updated]
    end

    test "sets controller_action for nested parameterized path" do
      route = create_route("GET", "/partners/acme/submissions/abc-123")

      call_backfiller

      assert_equal "home#index", route.reload.controller_action
    end

    test "sets controller_action for root path" do
      route = create_route("GET", "/")

      call_backfiller

      assert_equal "home#index", route.reload.controller_action
    end

    test "sets controller_action for POST-only route" do
      route = create_route("POST", "/errors/raise")

      call_backfiller

      assert_equal "home#raise_error", route.reload.controller_action
    end

    test "sets controller_action for namespaced controller" do
      route = create_route("POST", "/jobs/trigger")

      call_backfiller

      assert_equal "jobs#trigger", route.reload.controller_action
    end

    test "sets controller_action for warden-constrained route" do
      route = create_route("GET", "/warden_protected")

      call_backfiller

      assert_equal "home#index", route.reload.controller_action
    end

    test "sets controller_action for multi-verb route using first listed method" do
      route = create_route([ "GET", "POST" ], "/sign_in")

      call_backfiller

      assert_equal "home#index", route.reload.controller_action
    end

    test "sets controller_action when POST is listed before GET on multi-verb route" do
      route = create_route([ "POST", "GET" ], "/sign_in")

      call_backfiller

      assert_equal "home#index", route.reload.controller_action
    end

    test "sets controller_action for already-normalized path template" do
      route = create_route("GET", "/posts/:id")

      call_backfiller

      assert_equal "home#index", route.reload.controller_action
    end

    test "does not overwrite existing controller_action" do
      route = create_route("GET", "/posts/99", controller_action: "posts#show")

      results = call_backfiller

      assert_equal "posts#show", route.reload.controller_action
      assert_equal @baseline[:already_set] + 1, results[:already_set]
      assert_equal @baseline[:updated], results[:updated]
    end

    test "merges into existing route when controller_action would collide" do
      existing = create_route("GET", "/posts/99", controller_action: "home#index")
      duplicate = create_route("GET", "/posts/99")
      request = create_request(duplicate)

      results = call_backfiller

      assert_not RailsPulse::Route.exists?(id: duplicate.id)
      assert_equal existing.id, request.reload.route_id
      assert_equal [ "GET" ], existing.reload.http_methods_list
      assert_equal @baseline[:merged] + 1, results[:merged]
      assert_equal @baseline[:updated], results[:updated]
    end

    test "merges sibling null-controller_action routes that resolve to the same action" do
      first = create_route("GET", "/posts/99")
      call_backfiller
      second = create_route("GET", "/posts/99")
      request = create_request(second)

      call_backfiller

      survivor = RailsPulse::Route.find_by(controller_action: "home#index", path: "/posts/99")

      assert_not_nil survivor
      assert_equal 1, RailsPulse::Route.where(path: "/posts/99").count
      assert_equal survivor.id, request.reload.route_id
      assert_includes [ first.id, second.id ], survivor.id
    end

    test "merges different-verb siblings for the same path into one multi-verb route" do
      get_route = create_route("GET", "/sign_in")
      call_backfiller
      post_route = create_route("POST", "/sign_in")
      request = create_request(post_route)

      call_backfiller

      survivor = RailsPulse::Route.find_by(controller_action: "home#index", path: "/sign_in")

      assert_not_nil survivor
      assert_equal 1, RailsPulse::Route.where(path: "/sign_in").count
      assert_equal [ "GET", "POST" ], survivor.http_methods_list.sort
      assert_equal survivor.id, request.reload.route_id
      assert_includes [ get_route.id, post_route.id ], survivor.id
    end

    test "keeps GET and POST on the same path as separate routes when actions differ" do
      get_route = create_route("GET", "/users")
      call_backfiller
      post_route = create_route("POST", "/users")
      get_request = create_request(get_route)
      post_request = create_request(post_route)

      call_backfiller

      assert_equal "home#index", get_route.reload.controller_action
      assert_equal "home#create", post_route.reload.controller_action
      assert_equal 2, RailsPulse::Route.where(path: "/users").count
      assert_equal get_route.id, get_request.reload.route_id
      assert_equal post_route.id, post_request.reload.route_id
    end

    test "backfills blank controller_action string" do
      route = create_route("GET", "/posts/99", controller_action: "")

      call_backfiller

      assert_equal "home#index", route.reload.controller_action
    end

    test "backfills whitespace-only controller_action" do
      route = create_route("GET", "/posts/99", controller_action: "   ")

      call_backfiller

      assert_equal "home#index", route.reload.controller_action
    end

    test "leaves unrecognized paths unchanged" do
      route = create_route("GET", "/nonexistent/route/999")

      results = call_backfiller

      assert_nil route.reload.controller_action
      assert_equal @baseline[:skipped] + 1, results[:skipped]
    end

    test "backfills unrecognized path from request controller_action" do
      route = create_route("GET", "/error_prone")
      create_request(route, controller_action: "ErrorProneController#index")

      call_backfiller

      assert_equal "error_prone#index", route.reload.controller_action
    end

    test "normalizes namespaced request controller_action to controller#action" do
      route = create_route("GET", "/api/v1/users")
      create_request(route, controller_action: "Api::V1::UsersController#index")

      call_backfiller

      assert_equal "api/v1/users#index", route.reload.controller_action
    end

    test "prefers live router over historical request controller_action" do
      route = create_route("GET", "/posts/99")
      create_request(route, controller_action: "PostsController#show")

      call_backfiller

      assert_equal "home#index", route.reload.controller_action
    end

    test "uses most common request controller_action when router does not recognize" do
      route = create_route("GET", "/legacy/endpoint")
      2.times { create_request(route, controller_action: "LegacyController#show") }
      create_request(route, controller_action: "OtherController#index")

      call_backfiller

      assert_equal "legacy#show", route.reload.controller_action
    end

    # HTTP Method Edge Cases

    test "recognizes path using lowercase http method in http_methods JSON" do
      route = create_route_with_http_methods('["get"]', "/posts/99")

      call_backfiller

      assert_equal "home#index", route.reload.controller_action
    end

    test "skips route when first http method cannot recognize path" do
      route = create_route([ "POST", "GET" ], "/posts/99")

      results = call_backfiller

      assert_nil route.reload.controller_action
      assert_equal @baseline[:skipped] + 1, results[:skipped]
    end

    test "skips route with invalid http method in http_methods" do
      route = create_route_with_http_methods('["NOT_A_VERB"]', "/posts/99")

      results = call_backfiller

      assert_nil route.reload.controller_action
      assert_equal @baseline[:skipped] + 1, results[:skipped]
    end

    # http_methods Column Edge Cases

    test "skips route with empty http_methods array" do
      route = create_route_with_http_methods("[]", "/posts/99")

      results = call_backfiller

      assert_nil route.reload.controller_action
      assert_equal @baseline[:skipped] + 1, results[:skipped]
    end

    test "skips route with malformed http_methods JSON" do
      route = create_route_with_http_methods("not-json", "/posts/99")

      results = call_backfiller

      assert_nil route.reload.controller_action
      assert_equal @baseline[:skipped] + 1, results[:skipped]
    end

    test "uses only first http method when multiple are stored out of order" do
      route = create_route_with_http_methods('["PATCH","GET"]', "/posts/99")

      results = call_backfiller

      assert_nil route.reload.controller_action
      assert_equal @baseline[:skipped] + 1, results[:skipped]
    end

    # Results Hash Tests

    test "returns exact updated count for one backfillable route" do
      create_route("GET", "/posts/#{SecureRandom.hex(4)}")

      results = call_backfiller

      assert_equal @baseline[:updated] + 1, results[:updated]
    end

    test "returns exact skipped count for one unrecognized route" do
      create_route("GET", "/ghost/#{SecureRandom.hex(4)}")

      results = call_backfiller

      assert_equal @baseline[:skipped] + 1, results[:skipped]
    end

    test "returns exact already_set count for one preset route" do
      create_route("GET", "/posts/#{SecureRandom.hex(4)}", controller_action: "custom#show")

      results = call_backfiller

      assert_equal @baseline[:already_set] + 1, results[:already_set]
      assert_equal @baseline[:updated], results[:updated]
    end

    test "results hash has all expected keys" do
      results = call_backfiller

      assert_includes results.keys, :updated
      assert_includes results.keys, :skipped
      assert_includes results.keys, :already_set
      assert_includes results.keys, :merged
    end

    test "result counts sum to routes processed" do
      create_route("GET", "/posts/#{SecureRandom.hex(4)}")
      create_route("GET", "/ghost/#{SecureRandom.hex(4)}")
      create_route("GET", "/posts/#{SecureRandom.hex(4)}", controller_action: "preset#show")

      results = call_backfiller

      assert_equal RailsPulse::Route.count + results[:merged],
        results[:updated] + results[:skipped] + results[:already_set] + results[:merged]
    end

    test "processes multiple new routes in a single run" do
      backfillable = create_route("GET", "/posts/#{SecureRandom.hex(4)}")
      skipped = create_route("GET", "/ghost/#{SecureRandom.hex(4)}")
      preset = create_route("GET", "/posts/#{SecureRandom.hex(4)}", controller_action: "preset#show")

      results = call_backfiller

      assert_equal "home#index", backfillable.reload.controller_action
      assert_nil skipped.reload.controller_action
      assert_equal "preset#show", preset.reload.controller_action
      assert_equal @baseline[:updated] + 1, results[:updated]
      assert_equal @baseline[:skipped] + 1, results[:skipped]
      assert_equal @baseline[:already_set] + 1, results[:already_set]
    end

    # Idempotency Tests

    test "running twice does not change already-set routes" do
      route = create_route("GET", "/posts/99")
      call_backfiller
      first_value = route.reload.controller_action

      call_backfiller

      assert_equal first_value, route.reload.controller_action
    end

    test "second run updates nothing and counts all routes as already_set or skipped" do
      create_route("GET", "/posts/#{SecureRandom.hex(4)}")
      create_route("GET", "/ghost/#{SecureRandom.hex(4)}")
      call_backfiller

      results = call_backfiller

      assert_equal 0, results[:updated]
      assert_equal @baseline[:already_set] + 1, results[:already_set]
      assert_equal @baseline[:skipped] + 1, results[:skipped]
    end

    test "unrecognized routes remain skipped on every run" do
      route = create_route("GET", "/ghost/#{SecureRandom.hex(4)}")

      first = call_backfiller
      second = call_backfiller

      assert_nil route.reload.controller_action
      assert_equal @baseline[:skipped] + 1, first[:skipped]
      assert_equal @baseline[:skipped] + 1, second[:skipped]
    end

    private

    def call_backfiller
      RailsPulse::RouteControllerActionBackfiller.call
    end

    def create_route(http_method, path, controller_action: nil)
      methods = Array(http_method)
      RailsPulse::Route.create!(
        http_methods: methods.to_json,
        path: path,
        tags: "[]",
        controller_action: controller_action
      )
    end

    def create_route_with_http_methods(http_methods_json, path, controller_action: nil)
      RailsPulse::Route.create!(
        http_methods: http_methods_json,
        path: path,
        tags: "[]",
        controller_action: controller_action
      )
    end

    def create_request(route, controller_action: "PostsController#show")
      RailsPulse::Request.create!(
        route: route,
        method: route.http_methods_list.first || "GET",
        duration: 100.0,
        status: 200,
        is_error: false,
        request_uuid: SecureRandom.uuid,
        controller_action: controller_action,
        occurred_at: Time.current
      )
    end
  end
end
