require "test_helper"

module RailsPulse
  module Analysis
    class SuggestionGeneratorTest < ActiveSupport::TestCase
      def setup
        ENV["TEST_TYPE"] = "functional"
        super
      end

      # ============================================================================
      # Structure Tests
      # ============================================================================

      test "generate returns array" do
        generator = SuggestionGenerator.new({})

        result = generator.generate

        assert_kind_of Array, result
      end

      test "returns empty array for empty analysis results" do
        generator = SuggestionGenerator.new({})

        result = generator.generate

        assert_empty result
      end

      # ============================================================================
      # Query Characteristics Suggestions Tests
      # ============================================================================

      test "generates suggestion for SELECT * issue" do
        analysis_results = {
          query_characteristics: {
            pattern_issues: [
              { type: "select_star", severity: "info", description: "Using SELECT *" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        select_star_suggestion = result.find { |s| s[:action].include?("SELECT *") }
        assert_not_nil select_star_suggestion
        assert_equal "optimization", select_star_suggestion[:type]
        assert_equal "medium", select_star_suggestion[:priority]
        assert_equal "sql_optimization", select_star_suggestion[:category]
        assert_includes select_star_suggestion[:benefit], "memory"
      end

      test "generates suggestion for missing LIMIT issue" do
        analysis_results = {
          query_characteristics: {
            pattern_issues: [
              { type: "missing_limit", severity: "warning" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        limit_suggestion = result.find { |s| s[:action].include?("LIMIT") }
        assert_not_nil limit_suggestion
        assert_equal "high", limit_suggestion[:priority]
        assert_equal "sql_optimization", limit_suggestion[:category]
      end

      test "generates suggestion for missing WHERE clause" do
        analysis_results = {
          query_characteristics: {
            pattern_issues: [
              { type: "missing_where_clause", severity: "warning" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        where_suggestion = result.find { |s| s[:action].include?("WHERE") }
        assert_not_nil where_suggestion
        assert_equal "high", where_suggestion[:priority]
      end

      test "generates suggestion for complex WHERE clause" do
        analysis_results = {
          query_characteristics: {
            pattern_issues: [
              { type: "complex_where_clause", severity: "warning" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        complex_suggestion = result.find { |s| s[:action].include?("Simplify WHERE") }
        assert_not_nil complex_suggestion
        assert_equal "refactoring", complex_suggestion[:type]
        assert_equal "code_quality", complex_suggestion[:category]
      end

      # ============================================================================
      # Index Recommendation Suggestions Tests
      # ============================================================================

      test "generates suggestions from index recommendations" do
        analysis_results = {
          index_recommendations: [
            {
              type: "single_column",
              table: "users",
              columns: [ "email" ],
              priority: "high",
              migration_code: "add_index :users, :email",
              estimated_benefit: "Fast lookups"
            }
          ]
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        index_suggestion = result.first
        assert_equal "index", index_suggestion[:type]
        assert_includes index_suggestion[:action], "single_column index"
        assert_includes index_suggestion[:action], "add_index :users, :email"
        assert_equal "high", index_suggestion[:priority]
        assert_equal "database_optimization", index_suggestion[:category]
        assert_equal "users", index_suggestion[:table]
        assert_equal [ "email" ], index_suggestion[:columns]
      end

      test "generates multiple suggestions from multiple index recommendations" do
        analysis_results = {
          index_recommendations: [
            {
              type: "single_column",
              table: "users",
              columns: [ "email" ],
              priority: "high",
              migration_code: "add_index :users, :email",
              estimated_benefit: "Fast lookups"
            },
            {
              type: "composite",
              table: "posts",
              columns: [ "user_id", "published_at" ],
              priority: "medium",
              migration_code: "add_index :posts, [:user_id, :published_at]",
              estimated_benefit: "Efficient filtering"
            }
          ]
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        assert_equal 2, result.length
        assert result.all? { |s| s[:type] == "index" }
      end

      # ============================================================================
      # N+1 Query Suggestions Tests
      # ============================================================================

      test "generates suggestions for N+1 queries" do
        analysis_results = {
          n_plus_one_analysis: {
            is_likely_n_plus_one: true,
            confidence_score: 80,
            suggested_fixes: [
              {
                type: "includes",
                description: "Use includes() to eager load",
                code_example: "User.includes(:posts)"
              }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        n_plus_one_suggestion = result.find { |s| s[:type] == "n_plus_one" }
        assert_not_nil n_plus_one_suggestion
        assert_equal "high", n_plus_one_suggestion[:priority]
        assert_equal "performance_critical", n_plus_one_suggestion[:category]
        assert_includes n_plus_one_suggestion[:action], "includes()"
        assert_equal 80, n_plus_one_suggestion[:confidence]
      end

      test "does not generate N+1 suggestions when not detected" do
        analysis_results = {
          n_plus_one_analysis: {
            is_likely_n_plus_one: false,
            confidence_score: 0
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        n_plus_one_suggestions = result.select { |s| s[:type] == "n_plus_one" }
        assert_empty n_plus_one_suggestions
      end

      # ============================================================================
      # Query Characteristics Suggestions Tests
      # ============================================================================

      test "generates suggestion for excessive JOINs" do
        analysis_results = {
          query_characteristics: {
            join_count: 5,
            pattern_issues: []
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        join_suggestion = result.find { |s| s[:action].include?("JOINs") }
        assert_not_nil join_suggestion
        assert_equal "medium", join_suggestion[:priority]
      end

      test "generates suggestion for high complexity" do
        analysis_results = {
          query_characteristics: {
            estimated_complexity: 15,
            pattern_issues: []
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        complexity_suggestion = result.find { |s| s[:action].include?("complexity") }
        assert_not_nil complexity_suggestion
        assert_equal "refactoring", complexity_suggestion[:type]
      end

      test "generates suggestion for subqueries with JOINs" do
        analysis_results = {
          query_characteristics: {
            has_subqueries: true,
            join_count: 2,
            pattern_issues: []
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        subquery_suggestion = result.find { |s| s[:action].include?("subqueries") }
        assert_not_nil subquery_suggestion
      end

      # ============================================================================
      # EXPLAIN Plan Suggestions Tests
      # ============================================================================

      test "generates suggestion for sequential scan" do
        analysis_results = {
          explain_plan: {
            issues: [
              { type: "sequential_scan", severity: "warning" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        seq_scan_suggestion = result.find { |s| s[:action].include?("indexes") && s[:action].include?("WHERE") }
        assert_not_nil seq_scan_suggestion
        assert_equal "high", seq_scan_suggestion[:priority]
        assert_equal "database_optimization", seq_scan_suggestion[:category]
      end

      test "generates suggestion for temporary tables" do
        analysis_results = {
          explain_plan: {
            issues: [
              { type: "temporary_table", severity: "warning" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        temp_suggestion = result.find { |s| s[:action].include?("temporary tables") }
        assert_not_nil temp_suggestion
        assert_equal "medium", temp_suggestion[:priority]
      end

      test "generates suggestion for high cost operation" do
        analysis_results = {
          explain_plan: {
            issues: [
              { type: "high_cost_operation", severity: "warning" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        cost_suggestion = result.find { |s| s[:action].include?("high-cost") }
        assert_not_nil cost_suggestion
        assert_equal "high", cost_suggestion[:priority]
        assert_equal "performance_critical", cost_suggestion[:category]
      end

      # ============================================================================
      # Prioritization Tests
      # ============================================================================

      test "prioritizes high priority suggestions first" do
        analysis_results = {
          query_characteristics: {
            pattern_issues: [
              { type: "select_star", severity: "info" },  # medium priority
              { type: "missing_limit", severity: "warning" }  # high priority
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        assert_equal "high", result.first[:priority]
        assert_equal "medium", result.last[:priority]
      end

      test "prioritizes performance_critical category over others" do
        analysis_results = {
          query_characteristics: {
            pattern_issues: [
              { type: "select_star" }  # sql_optimization category
            ]
          },
          n_plus_one_analysis: {
            is_likely_n_plus_one: true,
            suggested_fixes: [
              { type: "includes", description: "Use includes()", code_example: "User.includes(:posts)" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        # N+1 (performance_critical) should come before SELECT * (sql_optimization) even if same priority
        assert_equal "performance_critical", result.first[:category]
      end

      test "deduplicates suggestions with same action" do
        analysis_results = {
          query_characteristics: {
            pattern_issues: [
              { type: "missing_limit" },
              { type: "missing_limit" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        limit_suggestions = result.select { |s| s[:action].include?("LIMIT") }
        assert_equal 1, limit_suggestions.length
      end

      # ============================================================================
      # Multiple Analyzer Integration Tests
      # ============================================================================

      test "combines suggestions from all analyzers" do
        analysis_results = {
          query_characteristics: {
            pattern_issues: [
              { type: "select_star" }
            ]
          },
          index_recommendations: [
            {
              type: "single_column",
              table: "users",
              columns: [ "email" ],
              priority: "high",
              migration_code: "add_index :users, :email",
              estimated_benefit: "Fast lookups"
            }
          ],
          n_plus_one_analysis: {
            is_likely_n_plus_one: true,
            suggested_fixes: [
              { type: "includes", description: "Use includes()", code_example: "User.includes(:posts)" }
            ]
          },
          explain_plan: {
            issues: [
              { type: "sequential_scan" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        types = result.map { |s| s[:type] }.uniq
        assert_includes types, "optimization"
        assert_includes types, "index"
        assert_includes types, "n_plus_one"
      end

      # ============================================================================
      # Edge Cases
      # ============================================================================

      test "handles missing nested data gracefully" do
        analysis_results = {
          query_characteristics: {}
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        assert_kind_of Array, result
      end

      test "handles nil values in analysis results" do
        analysis_results = {
          query_characteristics: nil,
          index_recommendations: nil,
          n_plus_one_analysis: nil
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        assert_empty result
      end

      test "skips nil suggestions from issue mapping" do
        analysis_results = {
          query_characteristics: {
            pattern_issues: [
              { type: "unknown_issue_type", severity: "warning" }
            ]
          }
        }
        generator = SuggestionGenerator.new(analysis_results)

        result = generator.generate

        # Unknown issue type should be skipped (returns nil, compacted)
        assert_empty result
      end
    end
  end
end
