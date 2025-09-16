require "test_helper"

module RailsPulse
  class QueryAnalysisServiceTest < ActiveSupport::TestCase
    setup do
      @query = create_query_with_operations
    end

    test "analyze_query returns comprehensive analysis results" do
      results = QueryAnalysisService.analyze_query(@query.id)

      assert_not_nil results[:analyzed_at]
      assert_not_nil results[:query_stats]
      assert_not_nil results[:backtrace_analysis]
      assert_instance_of Array, results[:issues]
      assert_instance_of Array, results[:suggestions]
    end

    test "analyzes query characteristics correctly" do
      results = QueryAnalysisService.analyze_query(@query.id)
      stats = results[:query_stats]

      assert_equal "SELECT", stats[:query_type]
      assert_equal 1, stats[:table_count]
      assert_equal 0, stats[:join_count]
      assert_equal false, stats[:has_subqueries]
      assert_equal false, stats[:has_limit]
      assert_equal false, stats[:has_order_by]
    end

    test "detects pattern-based issues" do
      # Create query with SELECT *
      query = create_query("SELECT * FROM users WHERE id = ?")
      results = QueryAnalysisService.analyze_query(query.id)

      select_star_issue = results[:issues].find { |issue| issue[:type] == "select_star" }
      assert_not_nil select_star_issue
      assert_equal "info", select_star_issue[:severity]
    end

    test "detects missing WHERE clause issues" do
      query = create_query("SELECT name FROM users")
      results = QueryAnalysisService.analyze_query(query.id)

      missing_where_issue = results[:issues].find { |issue| issue[:type] == "missing_where_clause" }
      assert_not_nil missing_where_issue
      assert_equal "warning", missing_where_issue[:severity]
    end

    test "analyzes backtrace data from recent operations" do
      results = QueryAnalysisService.analyze_query(@query.id)
      backtrace_analysis = results[:backtrace_analysis]

      assert_equal 3, backtrace_analysis[:total_executions]
      assert_equal 2, backtrace_analysis[:unique_locations]
      assert_equal "app/controllers/users_controller.rb:25", backtrace_analysis[:most_common_location]
    end

    test "generates relevant suggestions based on issues" do
      query = create_query("SELECT * FROM users WHERE name = ?")
      results = QueryAnalysisService.analyze_query(query.id)

      optimization_suggestion = results[:suggestions].find { |s| s[:type] == "optimization" }
      assert_not_nil optimization_suggestion
      assert_includes optimization_suggestion[:action], "specific columns"
    end

    test "saves analysis results to query model" do
      assert_nil @query.analyzed_at

      QueryAnalysisService.analyze_query(@query.id)
      @query.reload

      assert_not_nil @query.analyzed_at
      assert_not_nil @query.query_stats
      assert_not_nil @query.backtrace_analysis
      assert @query.analyzed?
    end

    test "handles queries without recent operations gracefully" do
      # Create query without any operations
      query = RailsPulse::Query.create!(normalized_sql: "SELECT COUNT(*) FROM posts")

      results = QueryAnalysisService.analyze_query(query.id)

      assert_not_nil results[:query_stats]
      assert_empty results[:backtrace_analysis]
      assert_nil results[:explain_plan]
    end

    test "detects N+1 query patterns" do
      # Create many operations in short time window
      query = create_query("SELECT * FROM posts WHERE user_id = ?")

      # Create 15 operations within 1 minute
      base_time = 1.minute.ago
      15.times do |i|
        create_operation(query, occurred_at: base_time + i.seconds)
      end

      results = QueryAnalysisService.analyze_query(query.id)

      assert results[:backtrace_analysis][:potential_n_plus_one]
    end

    test "calculates complexity score correctly" do
      complex_query = create_query(<<~SQL)
        SELECT u.name, p.title, COUNT(c.id) as comment_count
        FROM users u
        INNER JOIN posts p ON p.user_id = u.id
        LEFT JOIN comments c ON c.post_id = p.id
        WHERE u.active = ? AND p.published_at > ?
        GROUP BY u.id, p.id
        HAVING COUNT(c.id) > ?
        ORDER BY p.published_at DESC
      SQL

      results = QueryAnalysisService.analyze_query(complex_query.id)
      stats = results[:query_stats]

      assert stats[:estimated_complexity] > 10
      assert_equal 3, stats[:table_count]
      assert_equal 2, stats[:join_count]
      assert stats[:has_group_by]
      assert stats[:has_having]
      assert stats[:has_order_by]
      assert stats[:has_aggregations]
    end

    private

    def create_query_with_operations
      query = create_query("SELECT id, name FROM users WHERE id = ?")

      # Create some operations with different locations
      create_operation(query, codebase_location: "app/controllers/users_controller.rb:25")
      create_operation(query, codebase_location: "app/controllers/users_controller.rb:25")
      create_operation(query, codebase_location: "app/models/user.rb:15")

      query
    end

    def create_query(sql)
      RailsPulse::Query.create!(normalized_sql: sql)
    end

    def create_operation(query, attributes = {})
      route = RailsPulse::Route.find_or_create_by(method: "GET", path: "/users")
      request = RailsPulse::Request.create!(
        route: route,
        duration: 100.0,
        status: 200,
        is_error: false,
        request_uuid: SecureRandom.uuid,
        occurred_at: 1.hour.ago
      )

      default_attributes = {
        request: request,
        query: query,
        operation_type: "sql",
        label: query.normalized_sql,
        duration: 50.0,
        start_time: 0.0,
        occurred_at: 1.hour.ago,
        codebase_location: "app/models/user.rb:10"
      }

      RailsPulse::Operation.create!(default_attributes.merge(attributes))
    end
  end
end
