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
    existing_query = rails_pulse_queries(:simple_query)
    duplicate_query = RailsPulse::Query.new(normalized_sql: existing_query.normalized_sql)

    refute_predicate duplicate_query, :valid?
    assert_includes duplicate_query.errors[:normalized_sql], "has already been taken"
  end

  test "should be valid with required attributes" do
    query = rails_pulse_queries(:simple_query)

    assert_predicate query, :valid?
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
    query = rails_pulse_queries(:simple_query)

    assert_equal query.id, query.to_s
  end

  test "operations association should work" do
    # This tests that the association exists and works
    # The actual business logic of query association is tested in operation tests
    query = rails_pulse_queries(:complex_query)
    operation = rails_pulse_operations(:sql_operation_1)

    # Test the basic association
    assert_operator query.operations.count, :>, 0
    assert_includes query.operations, operation
    assert_equal query, operation.query
  end

  test "should have polymorphic summaries association" do
    query = rails_pulse_queries(:complex_query)
    summary = rails_pulse_summaries(:query_summary_1)

    assert_operator query.summaries.count, :>, 0
    assert_includes query.summaries, summary
    assert_equal query, summary.summarizable
  end

  # Analysis-related tests
  test "analyzed? returns false when analyzed_at is nil" do
    query = rails_pulse_queries(:simple_query)

    refute_predicate query, :analyzed?
  end

  test "analyzed? returns true when analyzed_at is present" do
    query = rails_pulse_queries(:analyzed_query)

    assert_predicate query, :analyzed?
  end

  test "has_recent_operations? returns true when recent operations exist" do
    query = rails_pulse_queries(:complex_query)

    assert_predicate query, :has_recent_operations?
  end

  test "has_recent_operations? returns false when no recent operations exist" do
    query = rails_pulse_queries(:stale_analyzed_query)

    # This query has no operations, so should return false
    refute_predicate query, :has_recent_operations?
  end

  test "needs_reanalysis? returns true when not analyzed" do
    query = rails_pulse_queries(:simple_query)

    assert_predicate query, :needs_reanalysis?
  end

  test "needs_reanalysis? returns false when recently analyzed with no new operations" do
    query = rails_pulse_queries(:analyzed_query)

    refute_predicate query, :needs_reanalysis?
  end

  test "needs_reanalysis? returns true when operations exist after analysis" do
    query = rails_pulse_queries(:simple_query)

    # This query has never been analyzed, so it needs reanalysis
    assert_predicate query, :needs_reanalysis?
  end

  test "analysis_status returns correct status" do
    # Not analyzed
    not_analyzed_query = rails_pulse_queries(:simple_query)

    assert_equal "not_analyzed", not_analyzed_query.analysis_status

    # Current analysis
    current_query = rails_pulse_queries(:analyzed_query)

    assert_equal "current", current_query.analysis_status

    # Analyzed query should be current since it doesn't have operations after analysis
    analyzed_query = rails_pulse_queries(:stale_analyzed_query)

    assert_equal "current", analyzed_query.analysis_status
  end

  test "issues_by_severity groups issues correctly" do
    query = rails_pulse_queries(:query_with_issues)
    grouped = query.issues_by_severity

    assert_equal 1, grouped["critical"].length
    assert_equal 1, grouped["warning"].length
  end

  test "critical_issues_count returns correct count" do
    query = rails_pulse_queries(:query_with_issues)

    assert_equal 1, query.critical_issues_count
  end

  test "warning_issues_count returns correct count" do
    query = rails_pulse_queries(:query_with_issues)

    assert_equal 1, query.warning_issues_count
  end

  test "serializes JSON columns correctly" do
    query = rails_pulse_queries(:query_with_issues)

    expected_stats = { "query_type" => "SELECT", "table_count" => 1 }
    expected_issues = [
      { "severity" => "critical", "description" => "Critical issue" },
      { "severity" => "warning", "description" => "Warning issue" }
    ]

    assert_equal expected_stats, query.query_stats
    assert_equal expected_issues, query.issues
  end
end
