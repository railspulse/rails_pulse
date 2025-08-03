require "test_helper"

class RailsPulse::OperationTest < ActiveSupport::TestCase
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

  test "should validate presence of required attributes" do
    # Test that operation_type is required
    operation = RailsPulse::Operation.new
    assert_not operation.valid?
    assert_includes operation.errors[:operation_type], "can't be blank"
    assert_includes operation.errors[:request_id], "can't be blank"
    assert_includes operation.errors[:label], "can't be blank"
    assert_includes operation.errors[:occurred_at], "can't be blank"
    assert_includes operation.errors[:duration], "can't be blank"
  end

  test "should validate operation_type inclusion" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "invalid_type",
      label: "User Load",
      duration: 25.5,
      occurred_at: Time.current
    )

    assert_not operation.valid?
    assert_includes operation.errors[:operation_type], "is not included in the list"
  end

  test "should be valid with all required attributes" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "sql",
      label: "User Load",
      duration: 25.5,
      occurred_at: Time.current
    )

    assert operation.valid?, "Operation should be valid but got errors: #{operation.errors.full_messages}"
  end

  test "should validate duration is non-negative" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "sql",
      label: "User Load",
      duration: -1.0,
      occurred_at: Time.current
    )

    assert_not operation.valid?
    assert_includes operation.errors[:duration], "must be greater than or equal to 0"
  end

  test "should accept zero duration" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "sql",
      label: "User Load",
      duration: 0.0,
      occurred_at: Time.current
    )

    assert operation.valid?
  end

  test "should have expected constants" do
    expected_types = %w[
      sql controller template partial layout collection
      cache_read cache_write http job mailer storage
    ]

    assert_equal expected_types.sort, RailsPulse::Operation::OPERATION_TYPES.sort
  end

  test "ransackable_attributes should return expected attributes" do
    expected_attributes = %w[id occurred_at label duration start_time average_query_time_ms query_count operation_type]
    assert_equal expected_attributes.sort, RailsPulse::Operation.ransackable_attributes.sort
  end

  test "to_s should return id" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.create!(
      request: request,
      operation_type: "sql",
      label: "User Load",
      duration: 25.5,
      occurred_at: Time.current
    )

    assert_equal operation.id, operation.to_s
  end

  test "by_type scope should filter by operation_type" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    sql_operation = RailsPulse::Operation.create!(
      request: request,
      operation_type: "sql",
      label: "User Load",
      duration: 25.5,
      occurred_at: Time.current
    )

    controller_operation = RailsPulse::Operation.create!(
      request: request,
      operation_type: "controller",
      label: "UsersController#index",
      duration: 50.0,
      occurred_at: Time.current
    )

    sql_operations = RailsPulse::Operation.by_type("sql")
    assert_includes sql_operations, sql_operation
    assert_not_includes sql_operations, controller_operation
  end

  test "should belong to query when operation_type is sql" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.create!(
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = 123",
      duration: 25.5,
      occurred_at: Time.current
    )

    assert_not_nil operation.query
    assert_equal "SELECT * FROM users WHERE id = ?", operation.query.normalized_sql
  end

  test "should not create query association for non-sql operations" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.create!(
      request: request,
      operation_type: "controller",
      label: "UsersController#index",
      duration: 25.5,
      occurred_at: Time.current
    )

    assert_nil operation.query
  end

  test "normalize_query_label should replace numeric values with placeholders" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = 123",
      duration: 25.5,
      occurred_at: Time.current
    )

    normalized = operation.send(:normalize_query_label, operation.label)
    assert_equal "SELECT * FROM users WHERE id = ?", normalized
  end

  test "normalize_query_label should replace quoted strings with placeholders" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE name = 'John Doe'",
      duration: 25.5,
      occurred_at: Time.current
    )

    normalized = operation.send(:normalize_query_label, operation.label)
    assert_equal "SELECT * FROM users WHERE name = ?", normalized
  end

  test "normalize_query_label should replace double quoted strings with placeholders" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "sql",
      label: 'SELECT * FROM users WHERE name = "John Doe"',
      duration: 25.5,
      occurred_at: Time.current
    )

    normalized = operation.send(:normalize_query_label, operation.label)
    assert_equal "SELECT * FROM users WHERE name = ?", normalized
  end

  test "normalize_query_label should replace floating point numbers with placeholders" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM products WHERE price > 19.99",
      duration: 25.5,
      occurred_at: Time.current
    )

    normalized = operation.send(:normalize_query_label, operation.label)
    # The improved implementation replaces floating-point numbers correctly
    assert_equal "SELECT * FROM products WHERE price > ?", normalized
  end

  test "normalize_query_label should handle IN clauses" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id IN (1, 2, 3, 4)",
      duration: 25.5,
      occurred_at: Time.current
    )

    normalized = operation.send(:normalize_query_label, operation.label)
    # The improved implementation preserves the number of parameters in IN clauses
    assert_equal "SELECT * FROM users WHERE id IN (?, ?, ?, ?)", normalized
  end

  test "normalize_query_label should handle comparison operators" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE age >= 18 AND score <= 100",
      duration: 25.5,
      occurred_at: Time.current
    )

    normalized = operation.send(:normalize_query_label, operation.label)
    assert_equal "SELECT * FROM users WHERE age >= ? AND score <= ?", normalized
  end

  test "normalize_query_label should handle blank input" do
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation = RailsPulse::Operation.new(
      request: request,
      operation_type: "sql",
      label: "",
      duration: 25.5,
      occurred_at: Time.current
    )

    normalized = operation.send(:normalize_query_label, "")
    assert_equal "", normalized

    normalized = operation.send(:normalize_query_label, nil)
    assert_nil normalized
  end

  test "associate_query callback should create or find existing query" do
    # Create first operation with a SQL query
    route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    request1 = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation1 = RailsPulse::Operation.create!(
      request: request1,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = 123",
      duration: 25.5,
      occurred_at: Time.current
    )

    initial_query = operation1.query
    assert_not_nil initial_query
    assert_equal "SELECT * FROM users WHERE id = ?", initial_query.normalized_sql

    # Create second operation with same normalized SQL
    request2 = RailsPulse::Request.create!(
      route: route,
      occurred_at: Time.current,
      duration: 100.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid
    )

    operation2 = RailsPulse::Operation.create!(
      request: request2,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = 456",
      duration: 30.0,
      occurred_at: Time.current
    )

    # Should reuse the same query
    assert_equal initial_query, operation2.query
    assert_equal 1, RailsPulse::Query.count
  end

  test "ransackers should be accessible without errors" do
    # Test that ransackers can be called (actual SQL testing would require more complex setup)
    assert_respond_to RailsPulse::Operation, :ransacker
  end
end
