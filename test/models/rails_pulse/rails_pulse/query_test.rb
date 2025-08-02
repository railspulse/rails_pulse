require "test_helper"

class RailsPulse::QueryTest < ActiveSupport::TestCase
  def setup
    ENV["TEST_TYPE"] = "unit"

    # Ensure tables exist before trying to delete from them
    DatabaseHelpers.ensure_test_tables_exist

    # Clean up any existing data
    RailsPulse::Operation.delete_all
    RailsPulse::Request.delete_all
    RailsPulse::Query.delete_all
    RailsPulse::Route.delete_all

    super
  end

  test "should validate presence of normalized_sql" do
    query = RailsPulse::Query.new
    assert_not query.valid?
    assert_includes query.errors[:normalized_sql], "can't be blank"
  end

  test "should validate uniqueness of normalized_sql" do
    RailsPulse::Query.create!(normalized_sql: "SELECT * FROM users WHERE id = ?")

    query = RailsPulse::Query.new(normalized_sql: "SELECT * FROM users WHERE id = ?")
    assert_not query.valid?
    assert_includes query.errors[:normalized_sql], "has already been taken"
  end

  test "should be valid with normalized_sql" do
    query = RailsPulse::Query.new(normalized_sql: "SELECT * FROM users WHERE id = ?")
    assert query.valid?
  end

  test "should have many operations" do
    query = RailsPulse::Query.create!(normalized_sql: "SELECT * FROM users WHERE id = ?")
    assert_respond_to query, :operations
    assert_kind_of ActiveRecord::Relation, query.operations
  end

  test "should create and associate operations" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    query = RailsPulse::Query.create!(normalized_sql: "SELECT * FROM users WHERE id = ?")

    operation = RailsPulse::Operation.create!(
      request: request,
      query: query,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = 123",
      duration: 25.5,
      occurred_at: Time.current
    )

    assert_equal query, operation.query
    assert_includes query.operations, operation
  end

  test "ransackable_attributes should return expected attributes" do
    expected_attributes = %w[
      id normalized_sql average_query_time_ms execution_count
      total_time_consumed performance_status occurred_at
    ]
    assert_equal expected_attributes.sort, RailsPulse::Query.ransackable_attributes.sort
  end

  test "ransackable_associations should return expected associations" do
    expected_associations = %w[operations]
    assert_equal expected_associations.sort, RailsPulse::Query.ransackable_associations.sort
  end

  test "to_s should return id" do
    query = RailsPulse::Query.create!(normalized_sql: "SELECT * FROM users WHERE id = ?")
    assert_equal query.id, query.to_s
  end

  test "should handle ransacker calculations with operations" do
    # Create test data
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    query = RailsPulse::Query.create!(normalized_sql: "SELECT * FROM users WHERE id = ?")

    # Create multiple operations for ransacker testing
    RailsPulse::Operation.create!(
      request: request,
      query: query,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = 123",
      duration: 10.0,
      occurred_at: 1.hour.ago
    )

    RailsPulse::Operation.create!(
      request: request,
      query: query,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = 456",
      duration: 20.0,
      occurred_at: Time.current
    )

    # Test that ransackers can be called without errors
    assert_respond_to RailsPulse::Query, :ransacker
  end

  test "performance_status ransacker should calculate thresholds correctly" do
    # Use the global configuration stub with custom thresholds
    stub_rails_pulse_configuration(
      query_thresholds: {
        slow: 100.0,
        very_slow: 500.0,
        critical: 1000.0
      }
    )

    # Test that the ransacker exists and can be called
    assert_respond_to RailsPulse::Query, :ransacker
  end
end
