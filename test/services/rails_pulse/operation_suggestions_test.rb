require "test_helper"

module RailsPulse
  class OperationSuggestionsTest < ActiveSupport::TestCase
    fixtures :rails_pulse_requests, :rails_pulse_operations, :rails_pulse_queries,
             :rails_pulse_job_runs

    def setup
      ENV["TEST_TYPE"] = "functional"
      super
    end

    # Structure Tests

    test "for returns an array" do
      operation = rails_pulse_operations(:sql_operation_1)

      result = OperationSuggestions.for(operation)

      assert_kind_of Array, result
    end

    test "each suggestion has required keys" do
      operation = rails_pulse_operations(:sql_operation_3) # duration 120ms → slow query suggestion
      request = rails_pulse_requests(:users_request_1)
      operation.update!(request: request)

      suggestions = OperationSuggestions.for(operation, parent: request)

      assert_predicate suggestions, :any?
      suggestions.each do |s|
        assert s.key?(:type),        "Missing :type in #{s.inspect}"
        assert s.key?(:icon),        "Missing :icon in #{s.inspect}"
        assert s.key?(:title),       "Missing :title in #{s.inspect}"
        assert s.key?(:description), "Missing :description in #{s.inspect}"
        assert s.key?(:priority),    "Missing :priority in #{s.inspect}"
      end
    end

    # SQL — Analysis Suggestions (stored from QueryAnalysisService)

    test "adapts stored analysis suggestions for SQL operations" do
      # Create op first so associate_query callback fires, then update its query's suggestions
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "sql",
        actual_sql: "SELECT * FROM accounts WHERE status = 'active'",
        occurred_at: Time.current,
        duration: 50
      )
      op.reload.query.update!(suggestions: [
        { "type" => "index", "action" => "Add index on accounts (status)", "benefit" => "Fast status lookups", "priority" => "high", "category" => "database_optimization" }
      ])

      suggestions = OperationSuggestions.for(op.reload)
      analysis_suggestion = suggestions.find { |s| s[:title] == "Add index on accounts (status)" }

      assert_not_nil analysis_suggestion
      assert_equal "index", analysis_suggestion[:type]
      assert_equal "database", analysis_suggestion[:icon]
      assert_equal "Fast status lookups", analysis_suggestion[:description]
      assert_equal "high", analysis_suggestion[:priority]
    end

    test "uses alert-triangle icon for performance_critical analysis suggestions" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "sql",
        actual_sql: "SELECT * FROM invoices WHERE user_id = 1",
        occurred_at: Time.current,
        duration: 50
      )
      op.reload.query.update!(suggestions: [
        { "type" => "n_plus_one", "action" => "Use eager loading", "benefit" => "Reduce queries", "priority" => "high", "category" => "performance_critical" }
      ])

      suggestions = OperationSuggestions.for(op.reload)
      s = suggestions.find { |s| s[:title] == "Use eager loading" }

      assert_not_nil s
      assert_equal "alert-triangle", s[:icon]
    end

    test "uses zap icon for sql_optimization analysis suggestions" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "sql",
        actual_sql: "SELECT * FROM products WHERE category = 'books'",
        occurred_at: Time.current,
        duration: 50
      )
      op.reload.query.update!(suggestions: [
        { "type" => "optimization", "action" => "Remove SELECT *", "benefit" => "Reduced data transfer", "priority" => "medium", "category" => "sql_optimization" }
      ])

      suggestions = OperationSuggestions.for(op.reload)
      s = suggestions.find { |s| s[:title] == "Remove SELECT *" }

      assert_not_nil s
      assert_equal "zap", s[:icon]
    end

    test "uses zap icon for unknown analysis suggestion category" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "sql",
        actual_sql: "SELECT * FROM subscriptions WHERE active = true",
        occurred_at: Time.current,
        duration: 50
      )
      op.reload.query.update!(suggestions: [
        { "type" => "custom", "action" => "Do something custom", "benefit" => "Better things", "priority" => "low", "category" => "unknown_category" }
      ])

      suggestions = OperationSuggestions.for(op.reload)
      s = suggestions.find { |s| s[:title] == "Do something custom" }

      assert_not_nil s
      assert_equal "zap", s[:icon]
    end

    test "skips analysis suggestions when query has none" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "sql",
        actual_sql: "SELECT * FROM sessions WHERE token = 'abc'",
        occurred_at: Time.current,
        duration: 50
      )
      # Newly created query has empty suggestions by default
      assert_empty op.reload.query.suggestions

      suggestions = OperationSuggestions.for(op.reload)

      refute suggestions.any? { |s| s[:title].nil? }
    end

    test "skips analysis suggestions when no associated query" do
      # A SQL label that does not parse as SELECT cannot have index suggestions either
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "sql",
        actual_sql: "BEGIN",
        occurred_at: Time.current,
        duration: 50
      )
      op.reload

      # Only runtime checks; no analysis suggestions to surface
      assert_kind_of Array, OperationSuggestions.for(op)
    end

    # SQL — Runtime: Slow Query

    test "generates slow query suggestion for SQL over 100ms" do
      operation = rails_pulse_operations(:sql_operation_1)
      operation.update!(duration: 150, query: nil, actual_sql: nil)

      suggestions = OperationSuggestions.for(operation)
      slow = suggestions.find { |s| s[:title] == "Slow Query Detected" }

      assert_not_nil slow
      assert_equal "performance", slow[:type]
      assert_equal "zap", slow[:icon]
      assert_equal "high", slow[:priority]
      assert_includes slow[:description], "150"
    end

    test "does not generate slow query suggestion for SQL at or under 100ms" do
      operation = rails_pulse_operations(:sql_operation_1)
      operation.update!(duration: 100, query: nil, actual_sql: nil)

      suggestions = OperationSuggestions.for(operation)

      refute suggestions.any? { |s| s[:title] == "Slow Query Detected" }
    end

    # SQL — Runtime: Index Optimization

    test "generates index suggestion for SELECT queries" do
      operation = rails_pulse_operations(:sql_operation_1)
      operation.update!(actual_sql: "SELECT * FROM orders WHERE status = 'pending'", query: nil, duration: 50)

      suggestions = OperationSuggestions.for(operation)
      index_s = suggestions.find { |s| s[:type] == "index" && s[:title] == "Index Optimization" }

      assert_not_nil index_s
      assert_equal "database", index_s[:icon]
      assert_equal "medium", index_s[:priority]
      assert_includes index_s[:description], "orders"
    end

    test "extracts table name from SELECT statement" do
      operation = rails_pulse_operations(:sql_operation_1)
      operation.update!(actual_sql: "SELECT id, name FROM accounts", query: nil, duration: 50)

      suggestions = OperationSuggestions.for(operation)
      index_s = suggestions.find { |s| s[:type] == "index" && s[:title] == "Index Optimization" }

      assert_not_nil index_s
      assert_includes index_s[:description], "accounts"
    end

    test "falls back to query normalized_sql for index check when actual_sql absent" do
      # Operations without actual_sql use label for query association; the service then
      # falls back to operation.query.normalized_sql to extract the table name.
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "sql",
        actual_sql: nil,
        label: "SELECT * FROM categories WHERE slug = ?",
        occurred_at: Time.current,
        duration: 50
      )
      op.reload

      assert_nil op.actual_sql
      assert_not_nil op.query

      suggestions = OperationSuggestions.for(op)
      index_s = suggestions.find { |s| s[:type] == "index" && s[:title] == "Index Optimization" }

      assert_not_nil index_s
      assert_includes index_s[:description], "categories"
    end

    test "does not generate index suggestion for non-SELECT SQL" do
      operation = rails_pulse_operations(:sql_operation_1)
      operation.update!(actual_sql: "UPDATE users SET name = 'test'", query: nil, duration: 50)

      suggestions = OperationSuggestions.for(operation)

      refute suggestions.any? { |s| s[:type] == "index" && s[:title] == "Index Optimization" }
    end

    # SQL — Runtime: N+1 Detection

    test "generates N+1 suggestion when more than 2 similar queries in parent" do
      request = rails_pulse_requests(:users_request_1)
      operation = rails_pulse_operations(:sql_operation_1)
      operation.update!(request: request, actual_sql: "SELECT * FROM users WHERE id = 1")

      3.times do |i|
        Operation.create!(
          request: request,
          operation_type: "sql",
          actual_sql: "SELECT * FROM users WHERE id = #{i + 2}",
          occurred_at: operation.occurred_at + (i + 1).seconds,
          duration: 10
        )
      end

      suggestions = OperationSuggestions.for(operation, parent: request)
      n1 = suggestions.find { |s| s[:type] == "n_plus_one" }

      assert_not_nil n1
      assert_equal "alert-triangle", n1[:icon]
      assert_equal "high", n1[:priority]
      assert_includes n1[:description], "similar queries detected"
    end

    test "does not generate N+1 suggestion with 2 or fewer similar queries" do
      request = rails_pulse_requests(:users_request_1)
      operation = rails_pulse_operations(:sql_operation_1)
      operation.update!(request: request, actual_sql: "SELECT * FROM users WHERE id = 1")

      Operation.create!(
        request: request,
        operation_type: "sql",
        actual_sql: "SELECT * FROM users WHERE id = 2",
        occurred_at: operation.occurred_at + 1.second,
        duration: 10
      )

      suggestions = OperationSuggestions.for(operation, parent: request)

      refute suggestions.any? { |s| s[:type] == "n_plus_one" }
    end

    test "skips N+1 check when no parent" do
      operation = rails_pulse_operations(:sql_operation_1)
      operation.update!(actual_sql: "SELECT * FROM users WHERE id = 1")

      suggestions = OperationSuggestions.for(operation, parent: nil)

      refute suggestions.any? { |s| s[:type] == "n_plus_one" }
    end

    test "skips N+1 check when operation has no query_id" do
      request = rails_pulse_requests(:users_request_1)
      operation = rails_pulse_operations(:sql_operation_1)
      operation.update!(request: request, query: nil, actual_sql: "SELECT * FROM users WHERE id = 1")

      suggestions = OperationSuggestions.for(operation, parent: request)

      refute suggestions.any? { |s| s[:type] == "n_plus_one" }
    end

    # SQL — Deduplication

    test "deduplicates suggestions with the same title" do
      query = rails_pulse_queries(:simple_query)
      query.update!(suggestions: [
        { "type" => "performance", "action" => "Slow Query Detected", "benefit" => "Better performance", "priority" => "high", "category" => "sql_optimization" }
      ])
      operation = rails_pulse_operations(:sql_operation_1)
      operation.update!(query: query, duration: 150, actual_sql: nil)

      suggestions = OperationSuggestions.for(operation)

      slow_count = suggestions.count { |s| s[:title] == "Slow Query Detected" }

      assert_equal 1, slow_count
    end

    # SQL — Empty Result

    test "returns empty array for fast non-SELECT SQL with no stored analysis" do
      # UPDATE/DELETE don't trigger the index pattern; fast duration skips slow-query suggestion
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "sql",
        actual_sql: "UPDATE sessions SET last_seen_at = NOW() WHERE id = 1",
        occurred_at: Time.current,
        duration: 50
      )
      op.reload # newly created query has empty suggestions

      suggestions = OperationSuggestions.for(op, parent: nil)

      assert_empty suggestions
    end

    # View Suggestions

    test "generates slow render suggestion for template over 100ms" do
      operation = rails_pulse_operations(:template_operation_1)
      operation.update!(duration: 150)

      suggestions = OperationSuggestions.for(operation)
      slow = suggestions.find { |s| s[:title] == "Slow View Rendering" }

      assert_not_nil slow
      assert_equal "performance", slow[:type]
      assert_equal "zap", slow[:icon]
      assert_equal "high", slow[:priority]
      assert_includes slow[:description], "150"
    end

    test "does not generate slow render suggestion for view at or under 100ms" do
      operation = rails_pulse_operations(:template_operation_1)
      operation.update!(duration: 100)

      suggestions = OperationSuggestions.for(operation)

      refute suggestions.any? { |s| s[:title] == "Slow View Rendering" }
    end

    test "generates DB in view suggestion when SQL operations occur during render" do
      request = rails_pulse_requests(:users_request_1)
      view_op = rails_pulse_operations(:template_operation_1)
      view_op.update!(request: request, occurred_at: Time.current, duration: 50)

      Operation.create!(
        request: request,
        operation_type: "sql",
        label: "SELECT * FROM users",
        occurred_at: view_op.occurred_at + 10,
        duration: 5
      )

      suggestions = OperationSuggestions.for(view_op, parent: request)
      db = suggestions.find { |s| s[:title] == "Database Queries in View" }

      assert_not_nil db
      assert_equal "database", db[:type]
      assert_equal "database", db[:icon]
      assert_equal "medium", db[:priority]
      assert_includes db[:description], "database queries during view rendering"
    end

    test "does not generate DB in view suggestion when no SQL during render" do
      request = rails_pulse_requests(:users_request_1)
      view_op = rails_pulse_operations(:template_operation_1)
      view_op.update!(request: request, occurred_at: Time.current, duration: 50)

      suggestions = OperationSuggestions.for(view_op, parent: request)

      refute suggestions.any? { |s| s[:title] == "Database Queries in View" }
    end

    test "skips DB in view check when no parent" do
      operation = rails_pulse_operations(:template_operation_1)
      operation.update!(duration: 50)

      suggestions = OperationSuggestions.for(operation, parent: nil)

      refute suggestions.any? { |s| s[:title] == "Database Queries in View" }
    end

    test "generates suggestions for partial operations" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "partial",
        label: "_user.html.erb",
        occurred_at: Time.current,
        duration: 120
      )

      suggestions = OperationSuggestions.for(op, parent: request)

      assert suggestions.any? { |s| s[:title] == "Slow View Rendering" }
    end

    test "generates suggestions for layout operations" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "layout",
        label: "application.html.erb",
        occurred_at: Time.current,
        duration: 110
      )

      suggestions = OperationSuggestions.for(op, parent: request)

      assert suggestions.any? { |s| s[:title] == "Slow View Rendering" }
    end

    test "generates suggestions for collection operations" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "collection",
        label: "_item.html.erb",
        occurred_at: Time.current,
        duration: 200
      )

      suggestions = OperationSuggestions.for(op, parent: request)

      assert suggestions.any? { |s| s[:title] == "Slow View Rendering" }
    end

    # Controller Suggestions

    test "generates slow controller suggestion for duration over 500ms" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "controller",
        label: "UsersController#index",
        occurred_at: Time.current,
        duration: 600
      )

      suggestions = OperationSuggestions.for(op)
      slow = suggestions.find { |s| s[:title] == "Slow Controller Action" }

      assert_not_nil slow
      assert_equal "performance", slow[:type]
      assert_equal "zap", slow[:icon]
      assert_equal "high", slow[:priority]
      assert_includes slow[:description], "600"
    end

    test "does not generate controller suggestion for duration at or under 500ms" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "controller",
        label: "UsersController#index",
        occurred_at: Time.current,
        duration: 500
      )

      suggestions = OperationSuggestions.for(op)

      assert_empty suggestions
    end

    # Cache Suggestions

    test "generates slow cache read suggestion for cache_read over 10ms" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "cache_read",
        label: "my_cache_key",
        occurred_at: Time.current,
        duration: 15
      )

      suggestions = OperationSuggestions.for(op)
      slow = suggestions.find { |s| s[:title] == "Slow Cache Read" }

      assert_not_nil slow
      assert_equal "performance", slow[:type]
      assert_equal "clock", slow[:icon]
      assert_equal "medium", slow[:priority]
      assert_includes slow[:description], "15"
    end

    test "does not generate cache suggestion for cache_read at or under 10ms" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "cache_read",
        label: "my_cache_key",
        occurred_at: Time.current,
        duration: 10
      )

      suggestions = OperationSuggestions.for(op)

      assert_empty suggestions
    end

    # HTTP Suggestions

    test "generates slow external request suggestion for HTTP over 1000ms" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "http",
        label: "GET https://api.example.com",
        occurred_at: Time.current,
        duration: 1500
      )

      suggestions = OperationSuggestions.for(op)
      slow = suggestions.find { |s| s[:title] == "Slow External Request" }

      assert_not_nil slow
      assert_equal "performance", slow[:type]
      assert_equal "globe", slow[:icon]
      assert_equal "high", slow[:priority]
      assert_includes slow[:description], "1500"
    end

    test "does not generate HTTP suggestion for requests at or under 1000ms" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "http",
        label: "GET https://api.example.com",
        occurred_at: Time.current,
        duration: 1000
      )

      suggestions = OperationSuggestions.for(op)

      assert_empty suggestions
    end

    # Unknown / Other Operation Types

    test "returns empty array for job operations" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "job",
        label: "MyJob",
        occurred_at: Time.current,
        duration: 5000
      )

      suggestions = OperationSuggestions.for(op)

      assert_empty suggestions
    end

    test "returns empty array for mailer operations" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "mailer",
        label: "UserMailer#welcome",
        occurred_at: Time.current,
        duration: 500
      )

      suggestions = OperationSuggestions.for(op)

      assert_empty suggestions
    end

    test "returns empty array for cache_write operations" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "cache_write",
        label: "my_cache_key",
        occurred_at: Time.current,
        duration: 20
      )

      suggestions = OperationSuggestions.for(op)

      assert_empty suggestions
    end

    test "returns empty array for storage operations" do
      request = rails_pulse_requests(:users_request_1)
      op = Operation.create!(
        request: request,
        operation_type: "storage",
        label: "upload",
        occurred_at: Time.current,
        duration: 2000
      )

      suggestions = OperationSuggestions.for(op)

      assert_empty suggestions
    end
  end
end
