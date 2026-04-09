require "test_helper"

class RailsPulse::RouteTest < ActiveSupport::TestCase
  include Shoulda::Matchers::ActiveModel
  include Shoulda::Matchers::ActiveRecord

  # Test associations
  test "should have correct associations" do
    assert have_many(:requests).dependent(:restrict_with_exception).matches?(RailsPulse::Route.new)
    assert have_many(:summaries).dependent(:destroy).matches?(RailsPulse::Route.new)
  end

  # Test validations
  test "should have correct validations" do
    route = RailsPulse::Route.new

    # Presence validations
    assert validate_presence_of(:method).matches?(route)
    assert validate_presence_of(:path).matches?(route)

    # Uniqueness validation with scope (test manually for cross-database compatibility)
    existing_route = rails_pulse_routes(:api_users)
    duplicate_route = RailsPulse::Route.new(method: existing_route.method, path: existing_route.path)

    refute_predicate duplicate_route, :valid?
    assert_includes duplicate_route.errors[:path], "and method combination must be unique"
  end

  test "should be valid with required attributes" do
    route = rails_pulse_routes(:api_users)

    assert_predicate route, :valid?
  end

  test "should include Taggable concern" do
    assert_includes RailsPulse::Route.included_modules, RailsPulse::Taggable
  end

  test "should include Taggable methods" do
    assert_respond_to RailsPulse::Route.new, :tag_list
  end

  test "should include ransackable attributes" do
    expected_attributes = %w[path average_response_time_ms max_response_time_ms request_count requests_per_minute occurred_at requests_occurred_at error_count error_rate_percentage status_indicator]

    assert_equal expected_attributes.sort, RailsPulse::Route.ransackable_attributes.sort
  end

  test "should include ransackable associations" do
    expected_associations = %w[requests]

    assert_equal expected_associations.sort, RailsPulse::Route.ransackable_associations.sort
  end

  test "should return path as breadcrumb" do
    route = rails_pulse_routes(:api_users)

    assert_equal "/api/users", route.to_breadcrumb
  end

  test "should return path and method" do
    route = rails_pulse_routes(:api_posts)

    assert_equal "/api/posts POST", route.path_and_method
  end

  test "requests association should return correct requests" do
    route1 = rails_pulse_routes(:api_users)
    route2 = rails_pulse_routes(:api_posts)

    # Get requests from fixtures
    request1 = rails_pulse_requests(:users_request_1)
    request2 = rails_pulse_requests(:posts_request)

    # Test that each route returns only its own requests
    assert_includes route1.requests, request1
    assert_not_includes route1.requests, request2

    assert_includes route2.requests, request2
    assert_not_includes route2.requests, request1
  end

  test "should have polymorphic summaries association" do
    route = rails_pulse_routes(:api_users)
    summary = rails_pulse_summaries(:route_summary_1)

    assert_includes route.summaries, summary
    assert_equal route, summary.summarizable
  end

  test "should calculate average response time" do
    # Use fixture data to test average response time calculation
    average = RailsPulse::Route.average_response_time

    assert_not_nil average
    assert_operator average, :>, 0
  end

  test "should handle restrict_with_exception on dependent destroy" do
    route = rails_pulse_routes(:api_users)

    # Should raise an exception when trying to delete a route with requests
    assert_raises(ActiveRecord::DeleteRestrictionError) do
      route.destroy!
    end
  end

  # ============================================================================
  # Scope Tests
  # ============================================================================

  test "by_method_and_path scope should find existing route" do
    existing_route = rails_pulse_routes(:api_users)

    found_route = RailsPulse::Route.by_method_and_path("GET", "/api/users")

    assert_equal existing_route, found_route
  end

  test "by_method_and_path scope should create new route when not found" do
    initial_count = RailsPulse::Route.count

    new_route = RailsPulse::Route.by_method_and_path("PUT", "/api/new_endpoint")

    assert_equal initial_count + 1, RailsPulse::Route.count
    assert_equal "PUT", new_route.method
    assert_equal "/api/new_endpoint", new_route.path
  end

  test "by_method_and_path scope should match both method and path" do
    # Create routes with same path but different methods
    route1 = RailsPulse::Route.by_method_and_path("GET", "/api/test")
    route2 = RailsPulse::Route.by_method_and_path("POST", "/api/test")

    refute_equal route1, route2
    assert_equal "GET", route1.method
    assert_equal "POST", route2.method
    assert_equal route1.path, route2.path
  end

  # ============================================================================
  # Ransacker Tests
  # ============================================================================

  test "average_response_time_ms ransacker should work with Ransack queries" do
    # Use Ransack to order by average response time
    search = RailsPulse::Route.ransack(s: "average_response_time_ms desc")
    results = search.result

    # Should return results without error
    assert_kind_of ActiveRecord::Relation, results
    assert_operator results.count, :>, 0
  end

  test "request_count ransacker should work with Ransack queries" do
    # Use Ransack to filter by request count
    search = RailsPulse::Route.ransack(s: "request_count desc")
    results = search.result

    # Should return results without error
    assert_kind_of ActiveRecord::Relation, results
    assert_operator results.count, :>, 0
  end

  test "error_rate_percentage ransacker should work with Ransack queries" do
    # Use Ransack to order by error rate
    search = RailsPulse::Route.ransack(s: "error_rate_percentage desc")
    results = search.result

    # Should return results without error
    assert_kind_of ActiveRecord::Relation, results
  end

  test "ransackers should calculate correct values from request data" do
    route = rails_pulse_routes(:api_users)

    # Use Ransack to get the route with calculated values
    search = RailsPulse::Route.ransack(path_eq: route.path)
    result = search.result.first

    assert_not_nil result
    assert_equal route, result
  end

  # ============================================================================
  # Instance Method Edge Cases
  # ============================================================================

  test "path_and_method should handle different HTTP methods" do
    methods = %w[GET POST PUT PATCH DELETE HEAD OPTIONS]

    methods.each do |http_method|
      route = RailsPulse::Route.create!(method: http_method, path: "/test/#{http_method.downcase}")
      expected = "/test/#{http_method.downcase} #{http_method}"

      assert_equal expected, route.path_and_method
    end
  end

  test "path_and_method should handle paths with special characters" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users/:id/posts")

    assert_equal "/api/users/:id/posts GET", route.path_and_method
  end

  test "to_breadcrumb should return path for different path formats" do
    paths = [
      "/api/users/:id",
      "/api/v1/posts/:post_id/comments",
      "/root/path"
    ]

    paths.each do |path_value|
      route = RailsPulse::Route.create!(method: "GET", path: path_value)

      assert_equal path_value, route.to_breadcrumb
    end
  end

  # ============================================================================
  # Class Method Edge Cases
  # ============================================================================

  test "average_response_time should return 0 when no routes exist" do
    # Delete in correct order to avoid foreign key constraints
    RailsPulse::Operation.delete_all
    RailsPulse::Request.delete_all
    RailsPulse::Summary.delete_all
    RailsPulse::Route.delete_all

    average = RailsPulse::Route.average_response_time

    assert_equal 0, average
  end

  test "average_response_time should calculate correct average from fixtures" do
    # Get all requests from fixtures and calculate expected average
    requests = RailsPulse::Request.all
    expected_avg = requests.sum(:duration) / requests.count.to_f

    actual_avg = RailsPulse::Route.average_response_time

    assert_in_delta expected_avg, actual_avg, 0.1
  end
end
