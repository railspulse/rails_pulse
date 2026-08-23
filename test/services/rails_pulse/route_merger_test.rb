require "test_helper"

module RailsPulse
  class RouteMergerTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes, :rails_pulse_requests

    test "moves requests from source to target and destroys source" do
      target = create_route("GET", "/posts/1", controller_action: "home#index")
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

    test "reassigns source summaries to target instead of destroying them" do
      target = create_route("GET", "/posts/1", controller_action: "home#index")
      source = create_route("POST", "/posts/1")
      summary = create_summary(source, count: 42)

      RailsPulse::RouteMerger.call(target: target, source: source)

      assert_not RailsPulse::Route.exists?(id: source.id)
      assert RailsPulse::Summary.exists?(id: summary.id),
        "expected source summary to survive merge, but dependent: :destroy deleted it"
      assert_equal target.id, summary.reload.summarizable_id
      assert_equal 42, summary.count
    end

    test "combines overlapping period summaries onto the target" do
      target = create_route("GET", "/posts/1", controller_action: "home#index")
      source = create_route("POST", "/posts/1")
      period_start = 1.hour.ago.beginning_of_hour

      target_summary = create_summary(target, count: 10, period_start: period_start, avg_duration: 100.0)
      source_summary = create_summary(source, count: 30, period_start: period_start, avg_duration: 200.0)

      RailsPulse::RouteMerger.call(target: target, source: source)

      assert_not RailsPulse::Summary.exists?(id: source_summary.id)
      target_summary.reload

      assert_equal target.id, target_summary.summarizable_id
      assert_equal 40, target_summary.count
      assert_in_delta 175.0, target_summary.avg_duration, 0.01
    end

    private

    def create_route(http_method, path, controller_action: nil)
      RailsPulse::Route.create!(
        http_methods: [ http_method ].to_json,
        path: path,
        tags: "[]",
        controller_action: controller_action
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

    def create_summary(route, count:, period_start: 1.hour.ago.beginning_of_hour, avg_duration: 100.0)
      RailsPulse::Summary.create!(
        summarizable: route,
        period_type: "hour",
        period_start: period_start,
        period_end: period_start.end_of_hour,
        count: count,
        avg_duration: avg_duration
      )
    end
  end
end
