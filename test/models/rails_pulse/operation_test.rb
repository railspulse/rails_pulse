require "test_helper"

class RailsPulse::OperationTest < ActiveSupport::TestCase
  include Shoulda::Matchers::ActiveModel
  include Shoulda::Matchers::ActiveRecord

  # Test associations
  test "should have correct associations" do
    assert belong_to(:request).matches?(RailsPulse::Operation.new)
    assert belong_to(:query).optional.matches?(RailsPulse::Operation.new)
  end

  # Test validations
  test "should have correct validations" do
    operation = RailsPulse::Operation.new

    # Presence validations
    assert validate_presence_of(:request_id).matches?(operation)
    assert validate_presence_of(:operation_type).matches?(operation)
    assert validate_presence_of(:label).matches?(operation)
    assert validate_presence_of(:occurred_at).matches?(operation)
    assert validate_presence_of(:duration).matches?(operation)

    # Inclusion validation
    assert validate_inclusion_of(:operation_type).in_array(RailsPulse::Operation::OPERATION_TYPES).matches?(operation)

    # Numericality validation
    assert validate_numericality_of(:duration).is_greater_than_or_equal_to(0).matches?(operation)
  end

  test "should be valid with required attributes" do
    operation = create(:operation)
    assert operation.valid?
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
    request = create(:request)
    sql_operation = create(:operation, request: request, operation_type: "sql")
    controller_operation = create(:operation, request: request, operation_type: "controller")

    sql_operations = RailsPulse::Operation.by_type("sql")
    assert_includes sql_operations, sql_operation
    assert_not_includes sql_operations, controller_operation
  end

  test "should associate query for sql operations" do
    request = create(:request)
    operation = build(:operation,
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = ?"
    )

    operation.save!

    assert_not_nil operation.query
    assert_instance_of RailsPulse::Query, operation.query
  end

  test "should not associate query for non-sql operations" do
    request = create(:request)
    operation = create(:operation, :controller, :without_query,
      request: request,
      label: "UsersController#show"
    )

    assert_nil operation.query
  end

  test "should return id as string representation" do
    operation = create(:operation)
    assert_equal operation.id, operation.to_s
  end
end
