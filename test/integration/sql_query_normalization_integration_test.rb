require "test_helper"

class SqlQueryNormalizationIntegrationTest < ActiveSupport::TestCase
  test "Operation model uses SqlQueryNormalizer service for query association" do
    # Create a request for the operation
    request = create(:request)

    # Create an operation with a SQL query
    operation = RailsPulse::Operation.create!(
      request: request,
      operation_type: "sql",
      label: "SELECT users.* FROM users WHERE users.id = 123 AND users.email = 'test@example.com'",
      occurred_at: Time.current,
      duration: 50.0
    )

    # The operation should have created an associated query
    assert_not_nil operation.query

    # The query's normalized_sql should use the improved normalization
    expected_normalized = "SELECT users.* FROM users WHERE users.id = ? AND users.email = ?"
    assert_equal expected_normalized, operation.query.normalized_sql

    # Creating another operation with the same normalized query should reuse the existing query
    operation2 = RailsPulse::Operation.create!(
      request: request,
      operation_type: "sql",
      label: "SELECT users.* FROM users WHERE users.id = 456 AND users.email = 'other@example.com'",
      occurred_at: Time.current,
      duration: 75.0
    )

    # Both operations should reference the same query record
    assert_equal operation.query, operation2.query
    assert_equal expected_normalized, operation2.query.normalized_sql
  end

  test "Service normalization creates meaningful query groupings" do
    request = create(:request)

    # Create operations with different table/column combinations
    operations_data = [
      "SELECT users.* FROM users WHERE users.id = 123",
      "SELECT users.* FROM users WHERE users.id = 456", # Same structure, different value
      "SELECT posts.* FROM posts WHERE posts.id = 123", # Different table
      "SELECT users.name FROM users WHERE users.id = 789", # Different columns
      "SELECT users.* FROM users WHERE users.email = 'test@example.com'" # Different column
    ]

    operations = operations_data.map do |sql|
      RailsPulse::Operation.create!(
        request: request,
        operation_type: "sql",
        label: sql,
        occurred_at: Time.current,
        duration: 50.0
      )
    end

    # Check that we get the expected number of unique queries
    unique_queries = operations.map(&:query).uniq

    # First two should share the same query (same structure)
    assert_equal operations[0].query, operations[1].query

    # Others should have different queries
    assert_not_equal operations[0].query, operations[2].query # Different table
    assert_not_equal operations[0].query, operations[3].query # Different columns selected
    assert_not_equal operations[0].query, operations[4].query # Different column in WHERE

    # Verify the normalized SQL for each unique pattern
    normalized_sqls = unique_queries.map(&:normalized_sql).sort
    expected_patterns = [
      "SELECT posts.* FROM posts WHERE posts.id = ?",
      "SELECT users.* FROM users WHERE users.email = ?",
      "SELECT users.* FROM users WHERE users.id = ?",
      "SELECT users.name FROM users WHERE users.id = ?"
    ].sort

    assert_equal expected_patterns, normalized_sqls
  end

  test "Complex SQL queries are normalized while preserving structure" do
    request = create(:request)

    complex_queries = [
      {
        input: "SELECT users.name, posts.title FROM users JOIN posts ON users.id = posts.user_id WHERE users.created_at > '2023-01-01' AND posts.status IN ('published', 'draft')",
        expected: "SELECT users.name, posts.title FROM users JOIN posts ON users.id = posts.user_id WHERE users.created_at > ? AND posts.status IN (?, ?)"
      },
      {
        input: "UPDATE users SET last_login = '2024-01-01 12:00:00', login_count = login_count + 1 WHERE id = 123",
        expected: "UPDATE users SET last_login = ?, login_count = login_count + ? WHERE id = ?"
      },
      {
        input: "INSERT INTO user_sessions (user_id, token, created_at) VALUES (123, 'abc123', '2024-01-01')",
        expected: "INSERT INTO user_sessions (user_id, token, created_at) VALUES (?, ?, ?)"
      }
    ]

    complex_queries.each do |query_data|
      operation = RailsPulse::Operation.create!(
        request: request,
        operation_type: "sql",
        label: query_data[:input],
        occurred_at: Time.current,
        duration: 50.0
      )

      assert_equal query_data[:expected], operation.query.normalized_sql,
        "Failed for query: #{query_data[:input]}"
    end
  end
end
