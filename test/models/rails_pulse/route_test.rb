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
    existing_route = create(:route, method: "GET", path: "/api/test")
    duplicate_route = build(:route, method: "GET", path: "/api/test")
    refute duplicate_route.valid?
    assert_includes duplicate_route.errors[:path], "and method combination must be unique"
  end

  test "should be valid with required attributes" do
    route = create(:route)
    assert route.valid?
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
    route = create(:route, path: "/api/users")
    assert_equal "/api/users", route.to_breadcrumb
  end

  test "should return path and method" do
    route = create(:route, method: "POST", path: "/api/users")
    assert_equal "/api/users POST", route.path_and_method
  end

  test "requests association should return correct requests" do
    route1 = create(:route, path: "/api/users", method: "GET")
    route2 = create(:route, path: "/api/posts", method: "GET")

    # Create requests for route1
    request1 = create(:request, route: route1)
    request2 = create(:request, route: route1)

    # Create request for route2
    request3 = create(:request, route: route2)

    # Test that each route returns only its own requests
    assert_equal 2, route1.requests.count
    assert_includes route1.requests, request1
    assert_includes route1.requests, request2
    assert_not_includes route1.requests, request3

    assert_equal 1, route2.requests.count
    assert_includes route2.requests, request3
    assert_not_includes route2.requests, request1
    assert_not_includes route2.requests, request2
  end

  test "should have polymorphic summaries association" do
    route = create(:route)
    summary = create(:summary, summarizable: route)

    assert_equal 1, route.summaries.count
    assert_includes route.summaries, summary
    assert_equal route, summary.summarizable
  end

  test "should calculate average response time" do
    route = create(:route)
    create(:request, route: route, duration: 100)
    create(:request, route: route, duration: 200)

    # The average should be calculated from all routes
    average = RailsPulse::Route.average_response_time
    assert_equal 150.0, average
  end

  test "should handle restrict_with_exception on dependent destroy" do
    route = create(:route)
    create(:request, route: route)

    # Should raise an exception when trying to delete a route with requests
    assert_raises(ActiveRecord::DeleteRestrictionError) do
      route.destroy!
    end
  end
end
