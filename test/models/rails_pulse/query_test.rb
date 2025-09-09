require "test_helper"

class RailsPulse::QueryTest < ActiveSupport::TestCase
  include Shoulda::Matchers::ActiveModel
  include Shoulda::Matchers::ActiveRecord

  # Test associations
  test "should have correct associations" do
    assert have_many(:operations).inverse_of(:query).matches?(RailsPulse::Query.new)
    assert have_many(:summaries).dependent(:destroy).matches?(RailsPulse::Query.new)
  end

  # Test validations
  test "should have correct validations" do
    query = RailsPulse::Query.new

    # Presence validation
    assert validate_presence_of(:normalized_sql).matches?(query)

    # Uniqueness validation (test manually for cross-database compatibility)
    existing_query = create(:query)
    duplicate_query = build(:query, normalized_sql: existing_query.normalized_sql)
    refute duplicate_query.valid?
    assert_includes duplicate_query.errors[:normalized_sql], "has already been taken"
  end

  test "should be valid with required attributes" do
    query = create(:query)
    assert query.valid?
  end

  test "should include ransackable attributes" do
    expected_attributes = %w[id normalized_sql average_query_time_ms execution_count total_time_consumed performance_status occurred_at]
    assert_equal expected_attributes.sort, RailsPulse::Query.ransackable_attributes.sort
  end

  test "should include ransackable associations" do
    expected_associations = %w[operations]
    assert_equal expected_associations.sort, RailsPulse::Query.ransackable_associations.sort
  end

  test "should return id as string representation" do
    query = create(:query)
    assert_equal query.id, query.to_s
  end

  test "operations association should work" do
    # This tests that the association exists and works
    # The actual business logic of query association is tested in operation tests
    query = create(:query, normalized_sql: "SELECT * FROM users WHERE id = ?")
    request = create(:request)
    operation = create(:operation, :without_query,
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = ?",
      query: query
    )

    # Test the basic association
    assert_equal 1, query.operations.count
    assert_includes query.operations, operation
    assert_equal query, operation.query
  end

  test "should have polymorphic summaries association" do
    query = create(:query)
    summary = create(:summary, summarizable: query)

    assert_equal 1, query.summaries.count
    assert_includes query.summaries, summary
    assert_equal query, summary.summarizable
  end
end
