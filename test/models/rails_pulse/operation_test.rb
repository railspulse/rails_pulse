require "test_helper"

class RailsPulse::OperationTest < ActiveSupport::TestCase
  include Shoulda::Matchers::ActiveModel
  include Shoulda::Matchers::ActiveRecord

  # Test associations
  test "should have correct associations" do
    assert belong_to(:request).optional.matches?(RailsPulse::Operation.new)
    assert belong_to(:job_run).optional.matches?(RailsPulse::Operation.new)
    assert belong_to(:query).optional.matches?(RailsPulse::Operation.new)
  end

  # Test validations
  test "should have correct validations" do
    operation = RailsPulse::Operation.new

    # Presence validations
    assert validate_presence_of(:operation_type).matches?(operation)
    assert validate_presence_of(:label).matches?(operation)
    assert validate_presence_of(:occurred_at).matches?(operation)
    assert validate_presence_of(:duration).matches?(operation)

    # Inclusion validation
    assert validate_inclusion_of(:operation_type).in_array(RailsPulse::Operation::OPERATION_TYPES).matches?(operation)

    # Numericality validation
    assert validate_numericality_of(:duration).is_greater_than_or_equal_to(0).matches?(operation)
  end

  test "should require either request or job run" do
    operation = RailsPulse::Operation.new(
      operation_type: "sql",
      label: "TEST",
      duration: 10,
      occurred_at: Time.current
    )

    assert_not operation.valid?
    assert_includes operation.errors[:base], "Operation must belong to a request or a job run"

    operation.request = rails_pulse_requests(:users_request_1)

    assert_predicate operation, :valid?, "operation should be valid with request present"
  end

  test "should be valid with required attributes" do
    operation = rails_pulse_operations(:sql_operation_1)

    assert_predicate operation, :valid?
  end

  test "should have correct operation types constant" do
    expected_types = %w[sql controller template partial layout collection cache_read cache_write http job mailer storage]

    assert_equal expected_types, RailsPulse::Operation::OPERATION_TYPES
  end

  test "should include ransackable attributes" do
    expected_attributes = %w[id occurred_at label duration start_time average_query_time_ms query_count operation_type query_id]

    assert_equal expected_attributes.sort, RailsPulse::Operation.ransackable_attributes.sort
  end

  test "should include ransackable associations" do
    expected_associations = []

    assert_equal expected_associations.sort, RailsPulse::Operation.ransackable_associations.sort
  end

  test "should have by_type scope" do
    sql_operation = rails_pulse_operations(:sql_operation_1)
    controller_operation = rails_pulse_operations(:controller_operation_1)

    sql_operations = RailsPulse::Operation.by_type("sql")

    assert_includes sql_operations, sql_operation
    assert_not_includes sql_operations, controller_operation
  end

  test "should associate query for sql operations" do
    operation = rails_pulse_operations(:sql_operation_1)

    assert_not_nil operation.query
    assert_instance_of RailsPulse::Query, operation.query
    assert_equal "SELECT * FROM posts WHERE id = ?", operation.query.normalized_sql
  end

  test "should not associate query for non-sql operations" do
    operation = rails_pulse_operations(:template_operation_1)

    assert_nil operation.query
  end

  test "should return id as string representation" do
    operation = rails_pulse_operations(:sql_operation_1)

    assert_equal operation.id, operation.to_s
  end

  test "should load fixture data correctly" do
    # Test that we can access fixture operations
    sql_op = rails_pulse_operations(:sql_operation_1)
    controller_op = rails_pulse_operations(:controller_operation_1)
    template_op = rails_pulse_operations(:template_operation_1)
    sql_op_2 = rails_pulse_operations(:sql_operation_2)

    # Verify we loaded 4 operations from fixtures
    assert_not_nil sql_op
    assert_not_nil controller_op
    assert_not_nil template_op
    assert_not_nil sql_op_2

    # Verify operation types match
    assert_equal "sql", sql_op.operation_type
    assert_equal "controller", controller_op.operation_type
    assert_equal "template", template_op.operation_type
    assert_equal "sql", sql_op_2.operation_type

    # Verify labels match
    assert_equal "SELECT * FROM posts WHERE id = ?", sql_op.label
    assert_equal "UsersController#index", controller_op.label
    assert_equal "render users/index.html.erb", template_op.label
    assert_equal "SELECT * FROM posts WHERE id = ?", sql_op_2.label

    # Verify durations match
    assert_in_delta(45.0, sql_op.duration)
    assert_in_delta(25.0, controller_op.duration)
    assert_in_delta(25.0, template_op.duration)
    assert_in_delta(35.0, sql_op_2.duration)

    # Verify associations work (sql operations should have queries)
    assert_not_nil sql_op.query
    assert_nil controller_op.query
    assert_nil template_op.query
    assert_not_nil sql_op_2.query

    # Verify query associations point to correct fixture queries
    assert_equal "SELECT * FROM posts WHERE id = ?", sql_op.query.normalized_sql
    assert_equal "SELECT * FROM posts WHERE id = ?", sql_op_2.query.normalized_sql

    # Verify we have exactly 6 operations total (4 original + 2 added for queries)
    assert_equal 7, RailsPulse::Operation.count

    # Test that we can access other fixture types
    route = rails_pulse_routes(:api_users)
    request = rails_pulse_requests(:users_request_1)
    query = rails_pulse_queries(:complex_query)

    assert_not_nil route
    assert_not_nil request
    assert_not_nil query

    # Verify associations between fixtures work
    assert_equal route, request.route
    assert_equal query, sql_op.query
    assert_equal request, sql_op.request

    # Verify job operation is associated with job run only
    job_operation = rails_pulse_operations(:job_sql_operation)

    assert_nil job_operation.request
    assert_equal rails_pulse_job_runs(:report_run_retried), job_operation.job_run
  end
end
