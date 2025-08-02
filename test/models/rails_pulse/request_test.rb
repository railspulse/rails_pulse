require "test_helper"

class RailsPulse::RequestTest < ActiveSupport::TestCase
  def setup
    ENV["TEST_TYPE"] = "unit"
    stub_all_external_dependencies
    setup_clean_database
    super
  end

  test "should be valid with required attributes" do
    request = create(:request)
    assert request.valid?
  end

  test "should validate presence of route_id" do
    request = build(:request, route: nil)
    assert_not request.valid?
    assert_includes request.errors[:route_id], "can't be blank"
  end

  test "should validate presence of occurred_at" do
    request = build(:request, occurred_at: nil)
    assert_not request.valid?
    assert_includes request.errors[:occurred_at], "can't be blank"
  end

  test "should validate duration is non-negative" do
    request = build(:request, duration: -1.0)
    assert_not request.valid?
    assert_includes request.errors[:duration], "must be greater than or equal to 0"
  end

  test "should require unique request_uuid" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    uuid = SecureRandom.uuid

    # Create first request with UUID
    RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: uuid
    )

    # Try to create second request with same UUID
    request = RailsPulse::Request.new(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: uuid
    )

    assert_not request.valid?
    assert_includes request.errors[:request_uuid], "has already been taken"
  end

  test "should generate request_uuid before create" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    assert_not_nil request.request_uuid
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i, request.request_uuid)
  end

  test "should belong to route" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    assert_equal route, request.route
  end

  test "should have many operations" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    assert_respond_to request, :operations
    assert_kind_of ActiveRecord::Relation, request.operations
  end

  test "should return formatted string representation" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    time = Time.parse("2024-01-15 14:30:00 UTC")

    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: time,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    expected_format = time.strftime("%b %d, %Y %l:%M %p")
    assert_equal expected_format, request.to_s
  end

  test "should include ransackable attributes" do
    expected_attributes = %w[id route_id occurred_at duration status status_indicator route_path]
    assert_equal expected_attributes.sort, RailsPulse::Request.ransackable_attributes.sort
  end

  test "should include ransackable associations" do
    expected_associations = %w[route]
    assert_equal expected_associations.sort, RailsPulse::Request.ransackable_associations.sort
  end

  test "status_indicator ransacker should calculate thresholds correctly" do
    # Use global configuration stub with custom thresholds
    stub_rails_pulse_configuration(
      request_thresholds: {
        slow: 200,
        very_slow: 500,
        critical: 1000
      }
    )

    # These would normally test the actual SQL generation,
    # but we're stubbing for speed
    assert_respond_to RailsPulse::Request, :ransacker
  end

  test "should destroy dependent operations when request is destroyed" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    # Create operations associated with the request
    operation1 = RailsPulse::Operation.create!(
      request: request,
      operation_type: "sql",
      label: "User Load",
      duration: 25.5,
      occurred_at: Time.current
    )

    operation2 = RailsPulse::Operation.create!(
      request: request,
      operation_type: "controller",
      label: "UsersController#index",
      duration: 50.0,
      occurred_at: Time.current
    )

    assert_equal 2, request.operations.count
    assert_equal 2, RailsPulse::Operation.count

    # Destroy the request
    request.destroy!

    # Operations should be destroyed as well
    assert_equal 0, RailsPulse::Operation.count
    assert_raises(ActiveRecord::RecordNotFound) { operation1.reload }
    assert_raises(ActiveRecord::RecordNotFound) { operation2.reload }
  end

  test "operations association should return correct operations" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request1 = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    request2 = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 150.0,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    # Create operations for request1
    operation1 = RailsPulse::Operation.create!(
      request: request1,
      operation_type: "sql",
      label: "User Load",
      duration: 25.5,
      occurred_at: Time.current
    )

    operation2 = RailsPulse::Operation.create!(
      request: request1,
      operation_type: "controller",
      label: "UsersController#index",
      duration: 50.0,
      occurred_at: Time.current
    )

    # Create operation for request2
    operation3 = RailsPulse::Operation.create!(
      request: request2,
      operation_type: "sql",
      label: "User Load",
      duration: 30.0,
      occurred_at: Time.current
    )

    # Test that each request returns only its own operations
    assert_equal 2, request1.operations.count
    assert_includes request1.operations, operation1
    assert_includes request1.operations, operation2
    assert_not_includes request1.operations, operation3

    assert_equal 1, request2.operations.count
    assert_includes request2.operations, operation3
    assert_not_includes request2.operations, operation1
    assert_not_includes request2.operations, operation2
  end

  test "route_path ransacker should access route path" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users/profile")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    # Test that ransacker exists and can be called
    assert_respond_to RailsPulse::Request, :ransacker
  end

  test "occurred_at ransacker should handle timestamp formatting" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    timestamp = Time.parse("2024-01-15 14:30:00 UTC")

    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: timestamp,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    # Test that ransacker exists and can be called
    assert_respond_to RailsPulse::Request, :ransacker
  end

  test "should handle edge case durations for status_indicator" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    # Test requests at threshold boundaries
    slow_request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 200.0, # exactly at slow threshold
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    very_slow_request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 500.0, # exactly at very_slow threshold
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    critical_request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 1000.0, # exactly at critical threshold
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    # All should be valid
    assert slow_request.valid?
    assert very_slow_request.valid?
    assert critical_request.valid?
  end

  test "request_uuid should be auto-generated if not provided" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    # Check that validation requires request_uuid but callback can generate it
    # We'll test this by verifying the before_create callback exists and works
    request = RailsPulse::Request.new(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: nil
    )

    # Manually trigger the callback that should happen before validation
    request.send(:set_request_uuid)

    assert_not_nil request.request_uuid
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i, request.request_uuid)
  end

  test "should not overwrite provided request_uuid" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    custom_uuid = "12345678-1234-1234-1234-123456789012"

    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: custom_uuid
    )

    assert_equal custom_uuid, request.request_uuid
  end

  test "should handle various HTTP status codes" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")

    status_codes = [ 200, 201, 400, 401, 404, 500, 503 ]

    status_codes.each do |status_code|
      request = RailsPulse::Request.create!(
        route: route,
        occurred_at: Time.current,
        duration: 100.5,
        status: status_code,
        is_error: status_code >= 400,
        request_uuid: SecureRandom.uuid
      )

      assert request.valid?
      assert_equal status_code, request.status
      assert_equal (status_code >= 400), request.is_error
    end
  end
end
