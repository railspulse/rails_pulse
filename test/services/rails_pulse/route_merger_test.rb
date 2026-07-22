require "test_helper"

module RailsPulse
  class RouteMergerTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes, :rails_pulse_requests

    test "moves requests from source to target and destroys source" do
      target = create_route("GET", "/posts/1")
      source = create_route("POST", "/posts/1")
      request = create_request(source)

      RailsPulse::RouteMerger.call(target: target, source: source)

      assert_not RailsPulse::Route.exists?(id: source.id)
      assert_equal target.id, request.reload.route_id
      assert_equal [ "GET", "POST" ], target.reload.http_methods_list.sort
    end

    test "is a no-op when target and source are the same record" do
      route = create_route("GET", "/posts/1")

      assert_nothing_raised do
        RailsPulse::RouteMerger.call(target: route, source: route)
      end

      assert RailsPulse::Route.exists?(id: route.id)
    end

    private

    def create_route(http_method, path)
      RailsPulse::Route.create!(
        http_methods: [ http_method ].to_json,
        path: path,
        tags: "[]"
      )
    end

    def create_request(route)
      RailsPulse::Request.create!(
        route: route,
        method: route.http_methods_list.first,
        duration: 100.0,
        status: 200,
        is_error: false,
        request_uuid: SecureRandom.uuid,
        controller_action: "PostsController#show",
        occurred_at: Time.current
      )
    end
  end
end
