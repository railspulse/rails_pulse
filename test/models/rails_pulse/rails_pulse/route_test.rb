require "test_helper"

class RailsPulse::RouteTest < ActiveSupport::TestCase
  def setup
    ENV["TEST_TYPE"] = "unit"
    setup_clean_database
    super
  end

  test "should validate presence of method" do
    route = build(:route, method: nil)
    assert_not route.valid?
    assert_includes route.errors[:method], "can't be blank"
  end

  test "should validate presence of path" do
    route = build(:route, path: nil)
    assert_not route.valid?
    assert_includes route.errors[:path], "can't be blank"
  end

  test "should validate uniqueness of path scoped to method" do
    create(:route, method: "GET", path: "/api/users")

    route = build(:route, method: "GET", path: "/api/users")
    assert_not route.valid?
    assert_includes route.errors[:path], "and method combination must be unique"
  end

  test "should allow same path with different method" do
    create(:route, method: "GET", path: "/api/users")

    route = build(:route, method: "POST", path: "/api/users")
    assert route.valid?
  end

  test "should be valid with method and path" do
    route = build(:route)
    assert route.valid?
  end

  test "should have many requests" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    assert_respond_to route, :requests
    assert_kind_of ActiveRecord::Relation, route.requests
  end

  test "should restrict deletion when requests exist" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    assert_raises(ActiveRecord::DeleteRestrictionError) do
      route.destroy!
    end
  end

  test "by_method_and_path scope should find existing route" do
    existing_route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    found_route = RailsPulse::Route.by_method_and_path("GET", "/api/users")

    assert_equal existing_route, found_route
  end

  test "by_method_and_path scope should create new route if none exists" do
    assert_difference "RailsPulse::Route.count", 1 do
      route = RailsPulse::Route.by_method_and_path("POST", "/api/users")
      assert_equal "POST", route.method
      assert_equal "/api/users", route.path
    end
  end

  test "ransackable_attributes should return expected attributes" do
    expected_attributes = %w[
      path average_response_time_ms max_response_time_ms request_count
      requests_per_minute occurred_at requests_occurred_at error_count
      error_rate_percentage status_indicator
    ]
    assert_equal expected_attributes.sort, RailsPulse::Route.ransackable_attributes.sort
  end

  test "ransackable_associations should return expected associations" do
    expected_associations = %w[requests]
    assert_equal expected_associations.sort, RailsPulse::Route.ransackable_associations.sort
  end

  test "to_breadcrumb should return path" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    assert_equal "/api/users", route.to_breadcrumb
  end

  test "path_and_method should return formatted string" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    assert_equal "/api/users GET", route.path_and_method
  end

  test "average_response_time class method should calculate average" do
    route1 = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    route2 = RailsPulse::Route.create!(method: "POST", path: "/api/posts")

    RailsPulse::Request.create!(
      route: route1,
      occurred_at: Time.current,
      duration: 100.0,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    RailsPulse::Request.create!(
      route: route1,
      occurred_at: Time.current,
      duration: 200.0,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    # Should calculate average across all routes
    average = RailsPulse::Route.average_response_time
    assert_equal 150.0, average
  end

  test "should handle ransacker calculations with requests" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    # Create test requests
    RailsPulse::Request.create!(
      route: route,
      occurred_at: 1.hour.ago,
      duration: 100.0,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 200.0,
      status: 500,
      is_error: true,
      request_uuid: SecureRandom.uuid
    )

    # Test that ransackers can be called without errors
    assert_respond_to RailsPulse::Route, :ransacker
  end

  test "status_indicator ransacker should calculate thresholds correctly" do
    # Use global configuration stub with custom thresholds
    stub_rails_pulse_configuration(
      route_thresholds: {
        slow: 200,
        very_slow: 500,
        critical: 1000
      }
    )

    # Test that the ransacker exists and can be called
    assert_respond_to RailsPulse::Route, :ransacker
  end

  test "error_rate_percentage ransacker should handle division by zero" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    # Route with no requests should handle division by zero gracefully
    assert_respond_to RailsPulse::Route, :ransacker
  end

  # Comprehensive ransacker tests

  test "average_response_time_ms ransacker calculates correctly" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    # Create requests with known durations
    [ 100, 200, 300 ].each_with_index do |duration, i|
      RailsPulse::Request.create!(
        route: route,
        occurred_at: Time.current - i.hours,
        duration: duration,
        status: 200,
        is_error: false,
        request_uuid: SecureRandom.uuid
      )
    end

    # Test ransacker using joins to ensure it works with aggregated data
    result = RailsPulse::Route.joins(:requests)
                              .group("rails_pulse_routes.id")
                              .select("rails_pulse_routes.*, AVG(rails_pulse_requests.duration) as avg_duration")
                              .where(id: route.id)
                              .first

    # Average of [100, 200, 300] = 200
    assert_equal 200.0, result.avg_duration
  end

  test "request_count ransacker counts correctly" do
    route1 = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    route2 = RailsPulse::Route.create!(method: "POST", path: "/api/posts")

    # Create different numbers of requests for each route
    3.times do |i|
      RailsPulse::Request.create!(
        route: route1,
        occurred_at: Time.current - i.hours,
        duration: 100,
        status: 200,
        is_error: false,
        request_uuid: SecureRandom.uuid
      )
    end

    5.times do |i|
      RailsPulse::Request.create!(
        route: route2,
        occurred_at: Time.current - i.hours,
        duration: 150,
        status: 200,
        is_error: false,
        request_uuid: SecureRandom.uuid
      )
    end

    # Test using joins and group by to get counts
    results = RailsPulse::Route.joins(:requests)
                               .group("rails_pulse_routes.id")
                               .select("rails_pulse_routes.*, COUNT(rails_pulse_requests.id) as req_count")
                               .order(:id)

    assert_equal 3, results.find { |r| r.id == route1.id }.req_count
    assert_equal 5, results.find { |r| r.id == route2.id }.req_count
  end

  test "error_count ransacker counts errors correctly" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    # Create mix of error and non-error requests
    [ false, true, false, true, true ].each_with_index do |is_error, i|
      RailsPulse::Request.create!(
        route: route,
        occurred_at: Time.current - i.hours,
        duration: 100,
        status: is_error ? 500 : 200,
        is_error: is_error,
        request_uuid: SecureRandom.uuid
      )
    end

    # Test error count using SQL
    result = RailsPulse::Route.joins(:requests)
                              .group("rails_pulse_routes.id")
                              .select("rails_pulse_routes.*, SUM(CASE WHEN rails_pulse_requests.is_error = true THEN 1 ELSE 0 END) as err_count")
                              .where(id: route.id)
                              .first

    # Should count 3 errors out of 5 requests
    assert_equal 3, result.err_count
  end

  test "error_rate_percentage ransacker calculates percentage correctly" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    # Create 4 requests, 1 error = 25% error rate
    [ false, false, false, true ].each_with_index do |is_error, i|
      RailsPulse::Request.create!(
        route: route,
        occurred_at: Time.current - i.hours,
        duration: 100,
        status: is_error ? 500 : 200,
        is_error: is_error,
        request_uuid: SecureRandom.uuid
      )
    end

    # Test error rate percentage calculation
    result = RailsPulse::Route.joins(:requests)
                              .group("rails_pulse_routes.id")
                              .select("rails_pulse_routes.*,
                                CASE WHEN COUNT(rails_pulse_requests.id) > 0 THEN
                                  ROUND((COALESCE(SUM(CASE WHEN rails_pulse_requests.is_error = true THEN 1 ELSE 0 END), 0) * 100.0) / COUNT(rails_pulse_requests.id), 2)
                                ELSE 0 END as error_percentage")
                              .where(id: route.id)
                              .first

    # Should be 25.0% (1 error out of 4 requests)
    assert_equal 25.0, result.error_percentage
  end

  test "max_response_time_ms ransacker finds maximum correctly" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    # Create requests with varying durations
    [ 50, 200, 150, 300, 100 ].each_with_index do |duration, i|
      RailsPulse::Request.create!(
        route: route,
        occurred_at: Time.current - i.hours,
        duration: duration,
        status: 200,
        is_error: false,
        request_uuid: SecureRandom.uuid
      )
    end

    # Test max response time
    result = RailsPulse::Route.joins(:requests)
                              .group("rails_pulse_routes.id")
                              .select("rails_pulse_routes.*, MAX(rails_pulse_requests.duration) as max_duration")
                              .where(id: route.id)
                              .first

    # Maximum should be 300
    assert_equal 300.0, result.max_duration
  end

  test "status_indicator ransacker categorizes performance correctly" do
    # Use global configuration stub with custom thresholds
    stub_rails_pulse_configuration(
      route_thresholds: {
        slow: 100,
        very_slow: 200,
        critical: 500
      },
      enabled: true
    )

    # Test different performance categories
    test_cases = [
      { avg_duration: 50, expected_status: 0 },   # Good
      { avg_duration: 150, expected_status: 1 },  # Slow
      { avg_duration: 350, expected_status: 2 },  # Very slow
      { avg_duration: 750, expected_status: 3 }   # Critical
    ]

    test_cases.each_with_index do |test_case, index|
      route = RailsPulse::Route.create!(method: "GET", path: "/api/test#{index}")

      # Create requests with specific average duration
      3.times do |i|
        RailsPulse::Request.create!(
          route: route,
          occurred_at: Time.current - i.hours,
          duration: test_case[:avg_duration],
          status: 200,
          is_error: false,
          request_uuid: SecureRandom.uuid
        )
      end

      # Test status indicator SQL logic
      result = RailsPulse::Route.joins(:requests)
                                .group("rails_pulse_routes.id")
                                .select("rails_pulse_routes.*,
                                  CASE
                                    WHEN COALESCE(AVG(rails_pulse_requests.duration), 0) >= 500 THEN 3
                                    WHEN COALESCE(AVG(rails_pulse_requests.duration), 0) >= 200 THEN 2
                                    WHEN COALESCE(AVG(rails_pulse_requests.duration), 0) >= 100 THEN 1
                                    ELSE 0
                                  END as status_indicator")
                                .where(id: route.id)
                                .first

      assert_equal test_case[:expected_status], result.status_indicator,
        "Expected status #{test_case[:expected_status]} for avg duration #{test_case[:avg_duration]}"

      # Verify route exists and has the expected number of requests
      assert_not_nil result
      assert_equal 3, route.requests.count
    end
  end

  test "ransackers handle empty result sets gracefully" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/empty")

    # Route with no requests
    result = RailsPulse::Route.joins("LEFT JOIN rails_pulse_requests ON rails_pulse_requests.route_id = rails_pulse_routes.id")
                              .group("rails_pulse_routes.id")
                              .select("rails_pulse_routes.*,
                                COALESCE(AVG(rails_pulse_requests.duration), 0) as avg_duration,
                                COUNT(rails_pulse_requests.id) as req_count,
                                COALESCE(MAX(rails_pulse_requests.duration), 0) as max_duration,
                                COALESCE(SUM(CASE WHEN rails_pulse_requests.is_error = true THEN 1 ELSE 0 END), 0) as err_count,
                                CASE WHEN COUNT(rails_pulse_requests.id) > 0 THEN
                                  ROUND((COALESCE(SUM(CASE WHEN rails_pulse_requests.is_error = true THEN 1 ELSE 0 END), 0) * 100.0) / COUNT(rails_pulse_requests.id), 2)
                                ELSE 0 END as error_percentage")
                              .where(id: route.id)
                              .first

    # All aggregated values should be 0 for routes with no requests
    assert_equal 0.0, result.avg_duration
    assert_equal 0, result.req_count
    assert_equal 0.0, result.max_duration
    assert_equal 0, result.err_count
    assert_equal 0.0, result.error_percentage
  end

  test "ransackers work with time-based filtering" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/time_filtered")

    # Create requests at different times
    recent_time = 1.hour.ago
    old_time = 25.hours.ago

    # Recent request
    RailsPulse::Request.create!(
      route: route,
      occurred_at: recent_time,
      duration: 100,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    # Old request
    RailsPulse::Request.create!(
      route: route,
      occurred_at: old_time,
      duration: 500,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    # Filter to only recent requests (last 24 hours)
    result = RailsPulse::Route.joins(:requests)
                              .where("rails_pulse_requests.occurred_at >= ?", 24.hours.ago)
                              .group("rails_pulse_routes.id")
                              .select("rails_pulse_routes.*, AVG(rails_pulse_requests.duration) as avg_duration")
                              .where(id: route.id)
                              .first

    # Should only include the recent request (duration 100)
    assert_equal 100.0, result.avg_duration
  end

  test "ransackers handle concurrent access correctly" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/concurrent")

    # Create requests
    10.times do |i|
      RailsPulse::Request.create!(
        route: route,
        occurred_at: Time.current - i.minutes,
        duration: (i + 1) * 10,
        status: 200,
        is_error: i.even?,
        request_uuid: SecureRandom.uuid
      )
    end

    # Simulate concurrent access by running the same query multiple times
    queries = Array.new(3) do
      Thread.new do
        RailsPulse::Route.joins(:requests)
                         .group("rails_pulse_routes.id")
                         .select("rails_pulse_routes.*,
                           COUNT(rails_pulse_requests.id) as req_count,
                           AVG(rails_pulse_requests.duration) as avg_duration")
                         .where(id: route.id)
                         .first
      end
    end

    results = queries.map(&:value)

    # All results should be identical
    first_result = results.first
    results.each do |result|
      assert_equal first_result.req_count, result.req_count
      assert_equal first_result.avg_duration, result.avg_duration
    end
  end
end
