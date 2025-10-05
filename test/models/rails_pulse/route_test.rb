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
    existing_route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    duplicate_route = RailsPulse::Route.new(method: existing_route.method, path: existing_route.path)

    refute_predicate duplicate_route, :valid?
    assert_includes duplicate_route.errors[:path], "and method combination must be unique"
  end

  test "should be valid with required attributes" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    assert_predicate route, :valid?
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
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    assert_equal "/api/users", route.to_breadcrumb
  end

  test "should return path and method" do
    route = RailsPulse::Route.create!(method: "POST", path: "/users")

    assert_equal "/users POST", route.path_and_method
  end

  test "requests association should return correct requests" do
    route1 = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    route2 = RailsPulse::Route.create!(method: "GET", path: "/api/posts")

    # Create requests that reference these routes
    request1 = RailsPulse::Request.create!(route: route1, duration: 150.5, status: 200, request_uuid: "test-uuid-1", controller_action: "UsersController#index", occurred_at: 1.hour.ago)
    request2 = RailsPulse::Request.create!(route: route2, duration: 250.0, status: 200, request_uuid: "test-uuid-2", controller_action: "PostsController#index", occurred_at: 1.hour.ago)

    # Test that each route returns only its own requests
    assert_includes route1.requests, request1
    assert_not_includes route1.requests, request2

    assert_includes route2.requests, request2
    assert_not_includes route2.requests, request1
  end

  test "should have polymorphic summaries association" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    summary = RailsPulse::Summary.create!(
      summarizable: route,
      period_start: 1.hour.ago.beginning_of_hour,
      period_end: 1.hour.ago.end_of_hour,
      period_type: "hour",
      count: 150,
      avg_duration: 180.5
    )

    assert_includes route.summaries, summary
    assert_equal route, summary.summarizable
  end

  test "should calculate average response time" do
    # Create test data with known durations
    route1 = RailsPulse::Route.create!(method: "GET", path: "/api/test1")
    route2 = RailsPulse::Route.create!(method: "GET", path: "/api/test2")

    RailsPulse::Request.create!(route: route1, duration: 150.5, status: 200, request_uuid: "test-1", controller_action: "Test#action", occurred_at: 1.hour.ago)
    RailsPulse::Request.create!(route: route2, duration: 250.0, status: 200, request_uuid: "test-2", controller_action: "Test#action", occurred_at: 1.hour.ago)

    average = RailsPulse::Route.average_response_time

    assert_not_nil average
    assert_operator average, :>, 0
    assert_in_delta(200.25, average)  # (150.5 + 250.0) / 2
  end

  test "should handle restrict_with_exception on dependent destroy" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    RailsPulse::Request.create!(route: route, duration: 150.5, status: 200, request_uuid: "test-uuid", controller_action: "UsersController#index", occurred_at: 1.hour.ago)

    # Should raise an exception when trying to delete a route with requests
    assert_raises(ActiveRecord::DeleteRestrictionError) do
      route.destroy!
    end
  end
end
