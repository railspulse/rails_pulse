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

  # Analysis-related tests
  test "analyzed? returns false when analyzed_at is nil" do
    query = create(:query)
    refute query.analyzed?
  end

  test "analyzed? returns true when analyzed_at is present" do
    query = create(:query, analyzed_at: 1.hour.ago)
    assert query.analyzed?
  end

  test "has_recent_operations? returns true when recent operations exist" do
    query = create(:query)
    request = create(:request)
    create(:operation, :without_query,
      request: request,
      query: query,
      operation_type: "sql",
      label: query.normalized_sql,
      occurred_at: 1.hour.ago
    )

    assert query.has_recent_operations?
  end

  test "has_recent_operations? returns false when no recent operations exist" do
    query = create(:query)
    request = create(:request)
    create(:operation, :without_query,
      request: request,
      query: query,
      operation_type: "sql",
      label: query.normalized_sql,
      occurred_at: 3.days.ago
    )

    refute query.has_recent_operations?
  end

  test "needs_reanalysis? returns true when not analyzed" do
    query = create(:query)
    assert query.needs_reanalysis?
  end

  test "needs_reanalysis? returns false when recently analyzed with no new operations" do
    query = create(:query, analyzed_at: 1.hour.ago)
    refute query.needs_reanalysis?
  end

  test "needs_reanalysis? returns true when operations exist after analysis" do
    query = create(:query, analyzed_at: 2.hours.ago)
    request = create(:request)
    create(:operation, :without_query,
      request: request,
      query: query,
      operation_type: "sql",
      label: query.normalized_sql,
      occurred_at: 1.hour.ago
    )

    assert query.needs_reanalysis?
  end

  test "analysis_status returns correct status" do
    # Not analyzed
    query = create(:query)
    assert_equal "not_analyzed", query.analysis_status

    # Current analysis
    query.update!(analyzed_at: 1.hour.ago)
    assert_equal "current", query.analysis_status

    # Needs update
    request = create(:request)
    create(:operation, :without_query,
      request: request,
      query: query,
      operation_type: "sql",
      label: query.normalized_sql,
      occurred_at: 30.minutes.ago
    )
    assert_equal "needs_update", query.analysis_status
  end

  test "issues_by_severity groups issues correctly" do
    issues = [
      { "severity" => "critical", "description" => "Critical issue" },
      { "severity" => "warning", "description" => "Warning issue" },
      { "severity" => "critical", "description" => "Another critical issue" }
    ]

    query = create(:query, issues: issues, analyzed_at: Time.current)
    grouped = query.issues_by_severity

    assert_equal 2, grouped["critical"].length
    assert_equal 1, grouped["warning"].length
  end

  test "critical_issues_count returns correct count" do
    issues = [
      { "severity" => "critical", "description" => "Critical issue" },
      { "severity" => "warning", "description" => "Warning issue" },
      { "severity" => "critical", "description" => "Another critical issue" }
    ]

    query = create(:query, issues: issues, analyzed_at: Time.current)
    assert_equal 2, query.critical_issues_count
  end

  test "warning_issues_count returns correct count" do
    issues = [
      { "severity" => "critical", "description" => "Critical issue" },
      { "severity" => "warning", "description" => "Warning issue" },
      { "severity" => "warning", "description" => "Another warning issue" }
    ]

    query = create(:query, issues: issues, analyzed_at: Time.current)
    assert_equal 2, query.warning_issues_count
  end

  test "serializes JSON columns correctly" do
    query_stats = { "query_type" => "SELECT", "table_count" => 2 }
    issues = [ { "severity" => "warning", "description" => "Test issue" } ]

    query = create(:query)
    query.update!(
      query_stats: query_stats,
      issues: issues
    )

    query.reload
    assert_equal query_stats, query.query_stats
    assert_equal issues, query.issues
  end
end
