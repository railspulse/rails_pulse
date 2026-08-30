require "test_helper"

module RailsPulse
  module Analysis
    class ExplainPlanAnalyzerTest < ActiveSupport::TestCase
      fixtures :rails_pulse_queries, :rails_pulse_operations

      # Test subclass to access protected methods and mock EXPLAIN execution
      class TestExplainPlanAnalyzer < ExplainPlanAnalyzer
        attr_accessor :mock_explain_plan, :mock_database_adapter

        def generate_explain_plan(sql)
          mock_explain_plan
        end

        def database_adapter
          mock_database_adapter || super
        end

        # Expose protected methods for testing
        public :detect_explain_issues, :sequential_scan?, :temporary_operations?
        public :analyze_postgres_specific_issues, :analyze_mysql_specific_issues
        public :analyze_sqlite_specific_issues
      end

      def setup
        ENV["TEST_TYPE"] = "functional"
        super
        @query = rails_pulse_queries(:simple_query)
      end

      # ============================================================================
      # Structure Tests
      # ============================================================================

      test "analyze returns hash with required keys" do
        operations = [ create_operation ]
        analyzer = ExplainPlanAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_kind_of Hash, result
        assert_includes result.keys, :explain_plan
        assert_includes result.keys, :issues
      end

      # ============================================================================
      # Empty Operations Tests
      # ============================================================================

      test "returns default result for empty operations" do
        analyzer = ExplainPlanAnalyzer.new(@query, [])

        result = analyzer.analyze

        assert_nil result[:explain_plan]
        assert_empty result[:issues]
      end

      # ============================================================================
      # Test Environment Behavior
      # ============================================================================

      test "returns explain plan for SELECT queries in test environment" do
        operations = [ create_operation ]
        analyzer = ExplainPlanAnalyzer.new(@query, operations)

        result = analyzer.analyze

        # The Rails.env.test? guard was removed so EXPLAIN runs on SELECT.
        # On SQLite this returns EXPLAIN QUERY PLAN output; on PG/MySQL
        # it returns the planner's plan. Either way it should not be nil.
        assert_not_nil result[:explain_plan]
      end

      test "refuses to EXPLAIN non-SELECT statements" do
        query = rails_pulse_queries(:simple_query)
        op = create_operation(actual_sql: "DELETE FROM users WHERE id = 1")
        analyzer = ExplainPlanAnalyzer.new(query, [ op ])

        result = analyzer.analyze

        assert_nil result[:explain_plan]
      end

      # ============================================================================
      # Sequential Scan Detection Tests
      # ============================================================================

      test "detects sequential scan in EXPLAIN output" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = "Seq Scan on users  (cost=0.00..10.00 rows=100 width=100)"

        result = analyzer.analyze

        assert_not_nil result[:explain_plan]
        sequential_issue = result[:issues].find { |i| i[:type] == "sequential_scan" }

        assert_not_nil sequential_issue
        assert_equal "warning", sequential_issue[:severity]
        assert_includes sequential_issue[:description], "sequential"
      end

      test "detects table scan in EXPLAIN output" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = "Table scan on users"

        result = analyzer.analyze

        sequential_issue = result[:issues].find { |i| i[:type] == "sequential_scan" }

        assert_not_nil sequential_issue
      end

      test "detects full table scan in EXPLAIN output" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = "Full table scan on users"

        result = analyzer.analyze

        sequential_issue = result[:issues].find { |i| i[:type] == "sequential_scan" }

        assert_not_nil sequential_issue
      end

      test "does not detect sequential scan when using index" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = "Index Scan using idx_users_email on users"

        result = analyzer.analyze

        sequential_issue = result[:issues].find { |i| i[:type] == "sequential_scan" }

        assert_nil sequential_issue
      end

      # ============================================================================
      # Temporary Operations Detection Tests
      # ============================================================================

      test "detects temporary table usage" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = "Using temporary table for sorting"

        result = analyzer.analyze

        temp_issue = result[:issues].find { |i| i[:type] == "temporary_table" }

        assert_not_nil temp_issue
        assert_equal "warning", temp_issue[:severity]
        assert_includes temp_issue[:description], "temporary"
      end

      test "detects filesort operation" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = "Using filesort"

        result = analyzer.analyze

        temp_issue = result[:issues].find { |i| i[:type] == "temporary_table" }

        assert_not_nil temp_issue
      end

      test "detects using temporary" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = "Using temporary; Using filesort"

        result = analyzer.analyze

        temp_issue = result[:issues].find { |i| i[:type] == "temporary_table" }

        assert_not_nil temp_issue
      end

      # ============================================================================
      # PostgreSQL-Specific Issue Detection Tests
      # ============================================================================

      test "detects high cost operation in PostgreSQL EXPLAIN" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "postgresql"
        postgres_plan = "Seq Scan on users  (cost=0.00..1500.00 rows=1000 width=100)"
        analyzer.mock_explain_plan = postgres_plan

        result = analyzer.analyze

        high_cost_issue = result[:issues].find { |i| i[:type] == "high_cost_operation" }

        assert_not_nil high_cost_issue
        assert_includes high_cost_issue[:description], "high execution cost"
      end

      test "does not flag low cost operations in PostgreSQL" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "postgresql"
        postgres_plan = "Index Scan using idx_users on users  (cost=0.00..50.00 rows=10 width=100)"
        analyzer.mock_explain_plan = postgres_plan

        result = analyzer.analyze

        high_cost_issue = result[:issues].find { |i| i[:type] == "high_cost_operation" }

        assert_nil high_cost_issue
      end

      test "detects large hash join in PostgreSQL" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "postgresql"
        postgres_plan = "Hash Join  (cost=100.00..500.00 rows=15000 width=100)"
        analyzer.mock_explain_plan = postgres_plan

        result = analyzer.analyze

        hash_join_issue = result[:issues].find { |i| i[:type] == "large_hash_join" }

        assert_not_nil hash_join_issue
        assert_equal "info", hash_join_issue[:severity]
      end

      # ============================================================================
      # MySQL-Specific Issue Detection Tests
      # ============================================================================

      test "detects WHERE without index in MySQL" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "mysql2"
        mysql_plan = "Using where"
        analyzer.mock_explain_plan = mysql_plan

        result = analyzer.analyze

        where_issue = result[:issues].find { |i| i[:type] == "where_without_index" }

        assert_not_nil where_issue
        assert_equal "warning", where_issue[:severity]
      end

      test "does not flag WHERE with index in MySQL" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "mysql2"
        mysql_plan = "Using where; Using index"
        analyzer.mock_explain_plan = mysql_plan

        result = analyzer.analyze

        where_issue = result[:issues].find { |i| i[:type] == "where_without_index" }

        assert_nil where_issue
      end

      test "detects full scan on large table in MySQL" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "mysql2"
        mysql_plan = "type: ALL  rows: 5000"
        analyzer.mock_explain_plan = mysql_plan

        result = analyzer.analyze

        full_scan_issue = result[:issues].find { |i| i[:type] == "full_scan_large_table" }

        assert_not_nil full_scan_issue
        assert_includes full_scan_issue[:description], "5000 rows"
      end

      # ============================================================================
      # SQLite-Specific Issue Detection Tests
      # ============================================================================

      test "detects SCAN TABLE in SQLite" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "sqlite"
        sqlite_plan = "SCAN TABLE users"
        analyzer.mock_explain_plan = sqlite_plan

        result = analyzer.analyze

        scan_issue = result[:issues].find { |i| i[:type] == "table_scan" }

        assert_not_nil scan_issue
        assert_equal "warning", scan_issue[:severity]
      end

      test "detects missing index usage in SQLite with WHERE" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "sqlite"
        sqlite_plan = "SCAN TABLE users WHERE email=?"
        analyzer.mock_explain_plan = sqlite_plan

        result = analyzer.analyze

        # Should detect table_scan issue
        scan_issue = result[:issues].find { |i| i[:type] == "table_scan" }

        assert_not_nil scan_issue
      end

      # ============================================================================
      # Multiple Issues Tests
      # ============================================================================

      test "detects multiple issues in single EXPLAIN" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = "Seq Scan on users; Using temporary; Using filesort"

        result = analyzer.analyze

        assert_operator result[:issues].length, :>=, 2
        assert result[:issues].any? { |i| i[:type] == "sequential_scan" }
        assert result[:issues].any? { |i| i[:type] == "temporary_table" }
      end

      # ============================================================================
      # Edge Cases
      # ============================================================================

      test "handles nil EXPLAIN plan gracefully" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = nil

        result = analyzer.analyze

        assert_nil result[:explain_plan]
        assert_empty result[:issues]
      end

      test "handles empty EXPLAIN plan string" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = ""

        result = analyzer.analyze

        assert_empty result[:issues]
      end

      test "handles EXPLAIN plan without issues" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = "Index Scan using idx_users_email on users  (cost=0.00..8.27 rows=1 width=100)"

        result = analyzer.analyze

        assert_empty result[:issues]
      end

      test "handles multiple operations and uses first one" do
        operations = [
          create_operation(label: "SELECT * FROM users WHERE id = 1"),
          create_operation(label: "SELECT * FROM posts WHERE id = 1")
        ]
        analyzer = ExplainPlanAnalyzer.new(@query, operations)

        result = analyzer.analyze

        # Should process the first operation
        assert_kind_of Hash, result
      end

      # ============================================================================
      # Helper Method Tests
      # ============================================================================

      test "sequential_scan? detects seq scan keyword" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [])

        assert analyzer.sequential_scan?("Seq Scan on users")
        refute analyzer.sequential_scan?("Index Scan on users")
      end

      test "temporary_operations? detects temporary keywords" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [])

        assert analyzer.temporary_operations?("Using temporary table")
        assert analyzer.temporary_operations?("Using filesort")
        refute analyzer.temporary_operations?("Index Scan on users")
      end

      test "case insensitive issue detection" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_explain_plan = "SEQ SCAN on users"

        result = analyzer.analyze

        sequential_issue = result[:issues].find { |i| i[:type] == "sequential_scan" }

        assert_not_nil sequential_issue
      end

      # ============================================================================
      # SQL Sanitization Tests
      # ============================================================================

      test "sanitize_sql_for_explain removes trailing semicolon" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])

        sql = "SELECT * FROM users WHERE id = 1;"
        sanitized = analyzer.send(:sanitize_sql_for_explain, sql)

        assert_equal "SELECT * FROM users WHERE id = 1", sanitized
      end

      test "sanitize_sql_for_explain removes multiple trailing semicolons" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])

        sql = "SELECT * FROM users WHERE id = 1;;;"
        sanitized = analyzer.send(:sanitize_sql_for_explain, sql)

        assert_equal "SELECT * FROM users WHERE id = 1", sanitized
      end

      test "sanitize_sql_for_explain removes trailing semicolon with whitespace" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])

        sql = "SELECT * FROM users WHERE id = 1;  \n"
        sanitized = analyzer.send(:sanitize_sql_for_explain, sql)

        assert_equal "SELECT * FROM users WHERE id = 1", sanitized
      end

      test "sanitize_sql_for_explain strips leading and trailing whitespace" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])

        sql = "  \n SELECT * FROM users WHERE id = 1  \n  "
        sanitized = analyzer.send(:sanitize_sql_for_explain, sql)

        assert_equal "SELECT * FROM users WHERE id = 1", sanitized
      end

      test "sanitize_sql_for_explain handles already clean SQL" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])

        sql = "SELECT * FROM users WHERE id = 1"
        sanitized = analyzer.send(:sanitize_sql_for_explain, sql)

        assert_equal "SELECT * FROM users WHERE id = 1", sanitized
      end

      # ============================================================================
      # PostgreSQL Edge Cases
      # ============================================================================

      test "detects multiple hash joins in PostgreSQL" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "postgresql"
        postgres_plan = <<~PLAN
          Hash Join  (cost=100.00..500.00 rows=15000 width=100)
          -> Hash Join  (cost=50.00..250.00 rows=20000 width=50)
        PLAN
        analyzer.mock_explain_plan = postgres_plan

        result = analyzer.analyze

        hash_join_issues = result[:issues].select { |i| i[:type] == "large_hash_join" }

        # Should detect at least one large hash join
        assert_operator hash_join_issues.size, :>=, 1
      end

      test "handles PostgreSQL EXPLAIN with no cost information" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "postgresql"
        postgres_plan = "Seq Scan on users"
        analyzer.mock_explain_plan = postgres_plan

        result = analyzer.analyze

        # Should not raise error, sequential scan should still be detected
        sequential_issue = result[:issues].find { |i| i[:type] == "sequential_scan" }

        assert_not_nil sequential_issue
      end

      # ============================================================================
      # MySQL Edge Cases
      # ============================================================================

      test "detects full scan with different type formatting in MySQL" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "mysql2"
        mysql_plan = "type: ALL extra_data rows: 10000"
        analyzer.mock_explain_plan = mysql_plan

        result = analyzer.analyze

        full_scan_issue = result[:issues].find { |i| i[:type] == "full_scan_large_table" }

        assert_not_nil full_scan_issue
      end

      test "handles MySQL EXPLAIN with low row count" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "mysql2"
        mysql_plan = "type: ALL  rows: 10"
        analyzer.mock_explain_plan = mysql_plan

        result = analyzer.analyze

        # Should not flag full scan on small table (< 1000 rows)
        full_scan_issue = result[:issues].find { |i| i[:type] == "full_scan_large_table" }

        assert_nil full_scan_issue
      end

      # ============================================================================
      # SQLite Edge Cases
      # ============================================================================

      test "detects SQLite SCAN TABLE without USING INDEX" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "sqlite"
        sqlite_plan = "SCAN TABLE users"
        analyzer.mock_explain_plan = sqlite_plan

        result = analyzer.analyze

        table_scan_issue = result[:issues].find { |i| i[:type] == "table_scan" }

        assert_not_nil table_scan_issue
      end

      test "does not flag SQLite SCAN TABLE with USING INDEX" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "sqlite"
        sqlite_plan = "SCAN TABLE users USING INDEX idx_users"
        analyzer.mock_explain_plan = sqlite_plan

        result = analyzer.analyze

        # Should still flag table_scan but not no_index_usage
        table_scan_issue = result[:issues].find { |i| i[:type] == "table_scan" }
        no_index_issue = result[:issues].find { |i| i[:type] == "no_index_usage" }

        assert_not_nil table_scan_issue, "Should detect table scan"
        assert_nil no_index_issue, "Should not flag no_index_usage when using index"
      end

      test "detects SQLite SCAN TABLE with WHERE clause but no index" do
        analyzer = TestExplainPlanAnalyzer.new(@query, [ create_operation ])
        analyzer.mock_database_adapter = "sqlite"
        sqlite_plan = "SCAN TABLE users WHERE condition"
        analyzer.mock_explain_plan = sqlite_plan

        result = analyzer.analyze

        # Should detect both table_scan and no_index_usage
        table_scan_issue = result[:issues].find { |i| i[:type] == "table_scan" }
        no_index_issue = result[:issues].find { |i| i[:type] == "no_index_usage" }

        assert_not_nil table_scan_issue
        assert_not_nil no_index_issue
      end

      private

      def create_operation(attributes = {})
        default_attributes = {
          request: rails_pulse_requests(:users_request_1),
          query: @query,
          operation_type: "sql",
          label: "SELECT * FROM users WHERE id = ?",
          duration: 50.0,
          start_time: 0.0,
          occurred_at: 1.hour.ago
        }

        RailsPulse::Operation.create!(default_attributes.merge(attributes))
      end
    end
  end
end
