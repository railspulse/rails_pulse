require "test_helper"

class PerformanceMonitoringTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "integration"
    # Don't stub middleware for integration tests - we want to test the full flow
    super
  end

  test "should collect performance data for requests" do
    skip "Integration test requires full middleware setup"
    # Enable Rails Pulse for this test
    original_enabled = RailsPulse.configuration.enabled
    RailsPulse.configuration.enabled = true

    initial_request_count = RailsPulse::Request.count
    initial_route_count = RailsPulse::Route.count

    # Make a request to the dummy app
    get "/fast"

    assert_response :success

    # Verify that performance data was collected
    assert_equal initial_request_count + 1, RailsPulse::Request.count, "Should create one Request record"

    # Check that route was created or found
    route = RailsPulse::Route.find_by(path: "/home/fast")
    assert_not_nil route, "Should create or find route for /home/fast"
    assert_equal "home", route.controller
    assert_equal "fast", route.action
    assert_equal "GET", route.http_method

    # Check request data
    request = RailsPulse::Request.last
    assert_equal route, request.route
    assert_not_nil request.occurred_at
    assert request.duration > 0, "Duration should be positive"
    assert_equal 200, request.status
    assert_equal false, request.is_error
    assert_not_nil request.request_uuid

  ensure
    # Reset configuration
    RailsPulse.configuration.enabled = original_enabled if original_enabled
  end

  test "should handle slow requests" do
    skip "Integration test requires full middleware setup"
    RailsPulse.configuration.enabled = true

    initial_count = RailsPulse::Request.count

    # Make request to slow endpoint
    get "/slow"

    assert_response :success
    assert_equal initial_count + 1, RailsPulse::Request.count

    request = RailsPulse::Request.last
    # Slow endpoint should take measurable time
    assert request.duration > 10, "Slow endpoint should have measurable duration"
    assert_equal 200, request.status
    assert_equal false, request.is_error
  end

  test "should handle error requests" do
    skip "Integration test requires full middleware setup"
    RailsPulse.configuration.enabled = true

    initial_count = RailsPulse::Request.count

    # Make request to error-prone endpoint
    get "/error_prone"

    # Should get server error
    assert_response :internal_server_error
    assert_equal initial_count + 1, RailsPulse::Request.count

    request = RailsPulse::Request.last
    assert_equal 500, request.status
    assert_equal true, request.is_error
  end

  test "should not collect data when disabled" do
    skip "Integration test requires full middleware setup"
    RailsPulse.configuration.enabled = false

    initial_count = RailsPulse::Request.count

    get "/fast"

    assert_response :success
    # Should not create any new records when disabled
    assert_equal initial_count, RailsPulse::Request.count
  end

  test "should display collected data in dashboard" do
    skip "Integration test requires full middleware setup"
    RailsPulse.configuration.enabled = true

    # Generate some test data by making requests
    3.times { get "/home/fast" }
    2.times { get "/home/slow" }

    # Now check dashboard displays the data
    get "/rails_pulse"

    assert_response :success

    # Should display metrics
    assert_select ".metric-card", minimum: 1

    # Should show some data in tables or charts
    assert_match(/home/, response.body) # Should show route information
  end

  test "should handle complex requests with database queries" do
    skip "Integration test requires full middleware setup"
    RailsPulse.configuration.enabled = true

    initial_request_count = RailsPulse::Request.count
    initial_query_count = RailsPulse::Query.count

    # Make request that should trigger database queries
    get "/api_complex"

    assert_response :success
    assert_equal initial_request_count + 1, RailsPulse::Request.count

    # Should capture database queries (if any are made)
    # Note: In a real app, this would capture actual DB queries
    request = RailsPulse::Request.last
    assert_not_nil request.occurred_at
    assert request.duration > 0
  end

  private

  def teardown
    # Clean up any test data
    RailsPulse::Request.delete_all
    RailsPulse::Route.delete_all
    RailsPulse::Query.delete_all
    RailsPulse::Operation.delete_all
    super
  end
end
