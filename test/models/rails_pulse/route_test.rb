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
end
