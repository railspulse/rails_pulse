require "test_helper"

module RailsPulse
  module Analysis
    class BaseAnalyzerTest < ActiveSupport::TestCase
      fixtures :rails_pulse_queries, :rails_pulse_operations

      # Test subclass to access protected methods
      class TestAnalyzer < BaseAnalyzer
        attr_accessor :mock_database_adapter

        def analyze
          { test: true }
        end

        def database_adapter
          mock_database_adapter || super
        end

        # Expose protected methods for testing
        public :sql, :recent_operations, :postgresql?, :mysql?, :sqlite?
        public :extract_main_table, :extract_where_clause, :normalize_sql_for_pattern_detection
      end

      def setup
        ENV["TEST_TYPE"] = "functional"
        super
        @query = rails_pulse_queries(:simple_query)
        @operations = [
          rails_pulse_operations(:sql_operation_1),
          rails_pulse_operations(:sql_operation_2)
        ]
      end

      # ============================================================================
      # Initialization Tests
      # ============================================================================

      test "initializes with query and operations" do
        analyzer = BaseAnalyzer.new(@query, @operations)

        assert_equal @query, analyzer.query
        assert_equal @operations, analyzer.operations
      end

      test "initializes with query and empty operations" do
        analyzer = BaseAnalyzer.new(@query)

        assert_equal @query, analyzer.query
        assert_equal [], analyzer.operations
      end

      test "initializes and converts single operation to array" do
        single_operation = @operations.first
        analyzer = BaseAnalyzer.new(@query, single_operation)

        assert_equal @query, analyzer.query
        assert_kind_of Array, analyzer.operations
        assert_equal [ single_operation ], analyzer.operations
      end

      # ============================================================================
      # Abstract Method Tests
      # ============================================================================

      test "analyze raises NotImplementedError" do
        analyzer = BaseAnalyzer.new(@query, @operations)

        error = assert_raises NotImplementedError do
          analyzer.analyze
        end

        assert_includes error.message, "BaseAnalyzer"
        assert_includes error.message, "must implement #analyze"
      end

      test "subclass can override analyze method" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.analyze

        assert_kind_of Hash, result
        assert_equal true, result[:test]
      end

      # ============================================================================
      # SQL Accessor Tests
      # ============================================================================

      test "sql returns normalized_sql from query" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.sql

        assert_equal "SELECT * FROM users WHERE id = ?", result
      end

      test "sql memoizes result" do
        analyzer = TestAnalyzer.new(@query, @operations)

        first_call = analyzer.sql
        second_call = analyzer.sql

        assert_same first_call, second_call
      end

      # ============================================================================
      # Recent Operations Tests
      # ============================================================================

      test "recent_operations filters operations within 48 hours" do
        travel_to Time.current do
          recent_op = create_operation(occurred_at: 1.hour.ago)
          old_op = create_operation(occurred_at: 50.hours.ago)

          analyzer = TestAnalyzer.new(@query, [ recent_op, old_op ])
          result = analyzer.recent_operations

          assert_includes result, recent_op
          refute_includes result, old_op
        end
      end

      test "recent_operations returns empty array when all operations are old" do
        travel_to Time.current do
          old_op1 = create_operation(occurred_at: 50.hours.ago)
          old_op2 = create_operation(occurred_at: 100.hours.ago)

          analyzer = TestAnalyzer.new(@query, [ old_op1, old_op2 ])
          result = analyzer.recent_operations

          assert_empty result
        end
      end

      test "recent_operations includes operation exactly at 48 hours boundary" do
        travel_to Time.current do
          boundary_op = create_operation(occurred_at: 48.hours.ago + 1.second)

          analyzer = TestAnalyzer.new(@query, [ boundary_op ])
          result = analyzer.recent_operations

          assert_includes result, boundary_op
        end
      end

      test "recent_operations memoizes result" do
        analyzer = TestAnalyzer.new(@query, @operations)

        first_call = analyzer.recent_operations
        second_call = analyzer.recent_operations

        assert_same first_call, second_call
      end

      # ============================================================================
      # Database Adapter Detection Tests
      # ============================================================================

      test "database_adapter returns current adapter name in lowercase" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.database_adapter

        assert_kind_of String, result
        assert_equal result.downcase, result
        assert_includes [ "sqlite", "postgresql", "mysql", "mysql2" ], result
      end

      test "postgresql? returns true for postgresql adapter" do
        analyzer = TestAnalyzer.new(@query, @operations)
        analyzer.mock_database_adapter = "postgresql"

        assert analyzer.postgresql?
        refute analyzer.mysql?
        refute analyzer.sqlite?
      end

      test "mysql? returns true for mysql or mysql2 adapter" do
        analyzer = TestAnalyzer.new(@query, @operations)
        analyzer.mock_database_adapter = "mysql2"

        assert analyzer.mysql?
        refute analyzer.postgresql?
        refute analyzer.sqlite?
      end

      test "sqlite? returns true for sqlite adapter" do
        analyzer = TestAnalyzer.new(@query, @operations)
        analyzer.mock_database_adapter = "sqlite"

        assert analyzer.sqlite?
        refute analyzer.postgresql?
        refute analyzer.mysql?
      end

      # ============================================================================
      # SQL Parsing Tests - extract_main_table
      # ============================================================================

      test "extract_main_table returns table name from FROM clause" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_main_table("SELECT * FROM users WHERE id = 1")

        assert_equal "users", result
      end

      test "extract_main_table handles lowercase" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_main_table("select * from posts where id = 1")

        assert_equal "posts", result
      end

      test "extract_main_table handles mixed case FROM" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_main_table("SELECT * FrOm products WHERE id = 1")

        assert_equal "products", result
      end

      test "extract_main_table uses default sql parameter when not provided" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_main_table

        assert_equal "users", result
      end

      test "extract_main_table returns nil for SQL without FROM clause" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_main_table("INSERT INTO users (name) VALUES ('test')")

        assert_nil result
      end

      test "extract_main_table returns nil for empty string" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_main_table("")

        assert_nil result
      end

      # ============================================================================
      # SQL Parsing Tests - extract_where_clause
      # ============================================================================

      test "extract_where_clause returns WHERE conditions" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_where_clause("SELECT * FROM users WHERE id = 1")

        assert_equal "id = 1", result
      end

      test "extract_where_clause handles multiple conditions" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_where_clause("SELECT * FROM users WHERE id = 1 AND active = true")

        assert_equal "id = 1 AND active = true", result
      end

      test "extract_where_clause stops at ORDER BY" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_where_clause("SELECT * FROM users WHERE id = 1 ORDER BY name")

        assert_equal "id = 1", result.strip
      end

      test "extract_where_clause stops at GROUP BY" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_where_clause("SELECT * FROM users WHERE active = true GROUP BY role")

        assert_equal "active = true", result.strip
      end

      test "extract_where_clause stops at LIMIT" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_where_clause("SELECT * FROM users WHERE id > 10 LIMIT 5")

        assert_equal "id > 10", result.strip
      end

      test "extract_where_clause uses default sql parameter when not provided" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_where_clause

        assert_equal "id = ?", result
      end

      test "extract_where_clause returns nil for SQL without WHERE clause" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.extract_where_clause("SELECT * FROM users")

        assert_nil result
      end

      # ============================================================================
      # SQL Normalization Tests
      # ============================================================================

      test "normalize_sql_for_pattern_detection replaces numbers with placeholders" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.normalize_sql_for_pattern_detection("SELECT * FROM users WHERE id = 123")

        assert_equal "select * from users where id = ?", result
      end

      test "normalize_sql_for_pattern_detection replaces strings with placeholders" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.normalize_sql_for_pattern_detection("SELECT * FROM users WHERE name = 'John'")

        assert_equal "select * from users where name = ?", result
      end

      test "normalize_sql_for_pattern_detection replaces multiple strings" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.normalize_sql_for_pattern_detection("SELECT * FROM users WHERE name = 'John' AND email = 'john@example.com'")

        assert_equal "select * from users where name = ? and email = ?", result
      end

      test "normalize_sql_for_pattern_detection normalizes whitespace" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.normalize_sql_for_pattern_detection("SELECT  *   FROM    users WHERE  id = 1")

        assert_equal "select * from users where id = ?", result
      end

      test "normalize_sql_for_pattern_detection converts to lowercase" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.normalize_sql_for_pattern_detection("SELECT * FROM Users WHERE ID = 1")

        assert_equal "select * from users where id = ?", result
      end

      test "normalize_sql_for_pattern_detection strips leading and trailing whitespace" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.normalize_sql_for_pattern_detection("  SELECT * FROM users WHERE id = 1  ")

        assert_equal "select * from users where id = ?", result
      end

      test "normalize_sql_for_pattern_detection returns empty string for nil input" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.normalize_sql_for_pattern_detection(nil)

        assert_equal "", result
      end

      test "normalize_sql_for_pattern_detection returns empty string for empty input" do
        analyzer = TestAnalyzer.new(@query, @operations)

        result = analyzer.normalize_sql_for_pattern_detection("")

        assert_equal "", result
      end

      test "normalize_sql_for_pattern_detection handles complex SQL" do
        analyzer = TestAnalyzer.new(@query, @operations)

        complex_sql = "SELECT users.id, users.name FROM users WHERE users.age > 25 AND users.email = 'test@example.com' ORDER BY users.created_at DESC"
        result = analyzer.normalize_sql_for_pattern_detection(complex_sql)

        assert_equal "select users.id, users.name from users where users.age > ? and users.email = ? order by users.created_at desc", result
      end

      # ============================================================================
      # Edge Cases
      # ============================================================================

      test "handles empty operations array gracefully" do
        analyzer = TestAnalyzer.new(@query, [])

        assert_equal [], analyzer.operations
        assert_equal [], analyzer.recent_operations
      end

      test "handles nil operations converted to empty array" do
        analyzer = TestAnalyzer.new(@query, nil)

        assert_equal [], analyzer.operations
      end

      private

      def create_operation(attributes = {})
        default_attributes = {
          request: rails_pulse_requests(:users_request_1),
          query: @query,
          operation_type: "sql",
          label: "SELECT * FROM test",
          duration: 50.0,
          start_time: 0.0,
          occurred_at: 1.hour.ago,
          codebase_location: "app/models/test.rb:10"
        }

        RailsPulse::Operation.create!(default_attributes.merge(attributes))
      end
    end
  end
end
