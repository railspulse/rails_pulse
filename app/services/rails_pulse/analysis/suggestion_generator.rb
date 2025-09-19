# Consolidates analysis results into prioritized, actionable optimization suggestions.
# Combines insights from all analyzers and categorizes suggestions by impact and implementation complexity.
module RailsPulse
  module Analysis
    class SuggestionGenerator
      attr_reader :analysis_results

      def initialize(analysis_results)
        @analysis_results = analysis_results
      end

      def generate
        suggestions = []

        # Suggestions from pattern issues
        suggestions.concat(generate_issue_suggestions)

        # Suggestions from index recommendations
        suggestions.concat(generate_index_suggestions)

        # Suggestions from N+1 analysis
        suggestions.concat(generate_n_plus_one_suggestions)

        # Suggestions from query characteristics
        suggestions.concat(generate_query_characteristic_suggestions)

        # Suggestions from explain plan issues
        suggestions.concat(generate_explain_plan_suggestions)

        # Prioritize and deduplicate suggestions
        prioritize_suggestions(suggestions)
      end

      private

      def generate_issue_suggestions
        issues = analysis_results.dig(:query_characteristics, :pattern_issues) || []

        issues.map do |issue|
          case issue[:type]
          when "select_star"
            {
              type: "optimization",
              action: "Specify only needed columns instead of SELECT *",
              benefit: "Reduced memory usage and faster data transfer",
              priority: "medium",
              category: "sql_optimization"
            }
          when "missing_limit"
            {
              type: "optimization",
              action: "Add LIMIT clause to prevent large result sets",
              benefit: "Controlled memory usage and faster response times",
              priority: "high",
              category: "sql_optimization"
            }
          when "missing_where_clause"
            {
              type: "optimization",
              action: "Add WHERE clause to filter results",
              benefit: "Avoid full table scans and reduce data transfer",
              priority: "high",
              category: "sql_optimization"
            }
          when "complex_where_clause"
            {
              type: "refactoring",
              action: "Simplify WHERE clause by breaking into multiple queries or using views",
              benefit: "Easier maintenance and potentially better performance",
              priority: "medium",
              category: "code_quality"
            }
          end
        end.compact
      end

      def generate_index_suggestions
        recommendations = analysis_results[:index_recommendations] || []

        recommendations.map do |rec|
          {
            type: "index",
            action: "Add #{rec[:type]} index: #{rec[:migration_code]}",
            benefit: rec[:estimated_benefit],
            priority: rec[:priority],
            migration_code: rec[:migration_code],
            table: rec[:table],
            columns: rec[:columns],
            category: "database_optimization"
          }
        end
      end

      def generate_n_plus_one_suggestions
        n_plus_one = analysis_results[:n_plus_one_analysis] || {}
        return [] unless n_plus_one[:is_likely_n_plus_one]

        suggestions = n_plus_one[:suggested_fixes] || []

        suggestions.map do |fix|
          {
            type: "n_plus_one",
            action: fix[:description],
            benefit: "Eliminate N+1 queries and reduce database load",
            priority: "high",
            code_example: fix[:code_example],
            confidence: n_plus_one[:confidence_score],
            category: "performance_critical"
          }
        end
      end

      def generate_query_characteristic_suggestions
        stats = analysis_results[:query_characteristics] || {}
        suggestions = []

        if stats[:join_count] && stats[:join_count] > 3
          suggestions << {
            type: "optimization",
            action: "Review if all #{stats[:join_count]} JOINs are necessary",
            benefit: "Simplified query execution and better performance",
            priority: "medium",
            category: "sql_optimization"
          }
        end

        if stats[:estimated_complexity] && stats[:estimated_complexity] > 10
          suggestions << {
            type: "refactoring",
            action: "Consider breaking complex query (complexity: #{stats[:estimated_complexity]}) into smaller parts",
            benefit: "Easier maintenance and potentially better performance",
            priority: "medium",
            category: "code_quality"
          }
        end

        if stats[:has_subqueries] && stats[:join_count] && stats[:join_count] > 1
          suggestions << {
            type: "optimization",
            action: "Consider converting subqueries to JOINs for better performance",
            benefit: "More efficient query execution in most databases",
            priority: "medium",
            category: "sql_optimization"
          }
        end

        suggestions
      end

      def generate_explain_plan_suggestions
        explain_issues = analysis_results.dig(:explain_plan, :issues) || []

        explain_issues.map do |issue|
          case issue[:type]
          when "sequential_scan"
            {
              type: "index",
              action: "Consider adding database indexes for WHERE clause columns",
              benefit: "Dramatically faster query execution",
              priority: "high",
              category: "database_optimization"
            }
          when "temporary_table"
            {
              type: "optimization",
              action: "Optimize query to avoid temporary tables and filesort operations",
              benefit: "Reduced memory usage and faster execution",
              priority: "medium",
              category: "sql_optimization"
            }
          when "high_cost_operation"
            {
              type: "optimization",
              action: "Review query execution plan for high-cost operations",
              benefit: "Identify specific bottlenecks for targeted optimization",
              priority: "high",
              category: "performance_critical"
            }
          when "where_without_index"
            {
              type: "index",
              action: "Add indexes to support WHERE clause conditions",
              benefit: "Eliminate row-by-row filtering during query execution",
              priority: "high",
              category: "database_optimization"
            }
          end
        end.compact
      end

      def prioritize_suggestions(suggestions)
        # Remove duplicates based on action
        unique_suggestions = suggestions.uniq { |s| s[:action] }

        # Sort by priority and category
        unique_suggestions.sort_by do |suggestion|
          priority_score = case suggestion[:priority]
          when "high" then 3
          when "medium" then 2
          when "low" then 1
          else 0
          end

          category_score = case suggestion[:category]
          when "performance_critical" then 4
          when "database_optimization" then 3
          when "sql_optimization" then 2
          when "code_quality" then 1
          else 0
          end

          [ -priority_score, -category_score, suggestion[:action] ]
        end
      end
    end
  end
end
