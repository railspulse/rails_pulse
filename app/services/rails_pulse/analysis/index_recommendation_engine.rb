# Recommends database indexes to improve query performance.
# Analyzes WHERE clauses, JOINs, ORDER BY, and identifies opportunities for single-column, composite, and covering indexes.
module RailsPulse
  module Analysis
    class IndexRecommendationEngine < BaseAnalyzer
      def analyze
        return [] unless sql.present?

        recommendations = []

        # Analyze WHERE clause for single column indexes
        recommendations.concat(analyze_where_clause_indexes)

        # Analyze JOIN conditions for indexes
        recommendations.concat(analyze_join_indexes)

        # Analyze ORDER BY clauses for indexes
        recommendations.concat(analyze_order_by_indexes)

        # Analyze composite index opportunities
        recommendations.concat(analyze_composite_index_opportunities)

        # Check for covering index opportunities
        recommendations.concat(analyze_covering_index_opportunities)

        # Prioritize recommendations based on query frequency and complexity
        prioritize_recommendations(recommendations)
      end

      private

      def analyze_where_clause_indexes
        recommendations = []
        table_name = extract_main_table
        return recommendations unless table_name

        where_clause = extract_where_clause
        return recommendations unless where_clause

        # Find equality conditions (best for indexes)
        equality_conditions = where_clause.scan(/(\w+)\s*=\s*[?'"\d]/)
        equality_conditions.each do |column_match|
          column = column_match[0]
          next if reserved_word?(column)

          recommendations << build_index_recommendation(
            table_name, [ column ], "single_column", "high",
            "Equality condition in WHERE clause",
            "Fast lookups for #{column} = value queries"
          )
        end

        # Find range conditions
        range_conditions = where_clause.scan(/(\w+)\s*(?:>|<|>=|<=|BETWEEN)/i)
        range_conditions.each do |column_match|
          column = column_match[0]
          next if reserved_word?(column)

          recommendations << build_index_recommendation(
            table_name, [ column ], "single_column", "medium",
            "Range condition in WHERE clause",
            "Efficient range scans for #{column}"
          )
        end

        # Find LIKE patterns that could benefit from indexes
        analyze_like_conditions(table_name, where_clause, recommendations)

        recommendations
      end

      def analyze_like_conditions(table_name, where_clause, recommendations)
        like_conditions = where_clause.scan(/(\w+)\s*LIKE\s*'([^']+)'/i)
        like_conditions.each do |column, pattern|
          next if reserved_word?(column)

          if pattern.start_with?("%")
            # Leading wildcard - suggest full-text search instead
            recommendations << build_fulltext_recommendation(table_name, column)
          else
            # Prefix match can use regular index
            recommendations << build_index_recommendation(
              table_name, [ column ], "single_column", "medium",
              "LIKE with prefix pattern",
              "Prefix matching for #{column}"
            )
          end
        end
      end

      def analyze_join_indexes
        recommendations = []

        # Extract JOIN conditions
        join_matches = sql.scan(/JOIN\s+(\w+)\s+.*?ON\s+(\w+)\.(\w+)\s*=\s*(\w+)\.(\w+)/i)

        join_matches.each do |join_table, table1, col1, table2, col2|
          # Recommend indexes on join columns
          recommendations << build_index_recommendation(
            join_table, [ col2 ], "single_column", "high",
            "JOIN condition", "Fast JOIN execution"
          )

          # Also check the other side of the join if it's not the main table
          main_table = extract_main_table
          if table1 != main_table
            recommendations << build_index_recommendation(
              table1, [ col1 ], "single_column", "high",
              "JOIN condition", "Fast JOIN execution"
            )
          end
        end

        recommendations
      end

      def analyze_order_by_indexes
        recommendations = []
        table_name = extract_main_table
        return recommendations unless table_name

        order_columns = extract_order_columns
        return recommendations if order_columns.empty?

        if order_columns.length == 1
          column = order_columns.first
          recommendations << build_index_recommendation(
            table_name, [ column ], "single_column", "medium",
            "ORDER BY clause", "Avoid sorting for ORDER BY #{column}"
          )
        elsif order_columns.length > 1
          recommendations << build_index_recommendation(
            table_name, order_columns, "composite", "medium",
            "Multi-column ORDER BY", "Avoid sorting for complex ORDER BY"
          )
        end

        recommendations
      end

      def analyze_composite_index_opportunities
        recommendations = []
        table_name = extract_main_table
        return recommendations unless table_name

        where_columns = extract_where_columns
        order_columns = extract_order_columns

        # Look for WHERE + ORDER BY combinations
        if where_columns.any? && order_columns.any?
          composite_columns = where_columns + order_columns

          recommendations << build_index_recommendation(
            table_name, composite_columns, "composite", "high",
            "WHERE + ORDER BY optimization",
            "Single index for filtering and sorting"
          )
        end

        # Look for multiple WHERE conditions
        if where_columns.length > 1
          recommendations << build_index_recommendation(
            table_name, where_columns, "composite", "high",
            "Multiple WHERE conditions",
            "Efficient multi-column filtering"
          )
        end

        recommendations
      end

      def analyze_covering_index_opportunities
        recommendations = []
        table_name = extract_main_table
        return recommendations unless table_name

        # Extract selected columns
        select_match = sql.match(/SELECT\s+(.+?)\s+FROM/i)
        return recommendations if !select_match || select_match[1].include?("*")

        selected_columns = select_match[1].split(",").map(&:strip)
        where_columns = extract_where_columns

        if where_columns.any? && selected_columns.length <= 5
          covering_columns = (where_columns + selected_columns).uniq

          recommendations << {
            type: "covering",
            table: table_name,
            columns: covering_columns,
            reason: "Covering index opportunity",
            priority: "medium",
            migration_code: generate_covering_migration_code(table_name, where_columns, selected_columns),
            estimated_benefit: "Index-only scan without table access",
            priority_score: 60,
            execution_context: execution_context
          }
        end

        recommendations
      end

      def extract_where_columns
        where_clause = extract_where_clause
        return [] unless where_clause

        columns = []

        # Extract columns from equality conditions
        columns.concat(where_clause.scan(/(\w+)\s*=/).flatten)
        # Extract columns from range conditions
        columns.concat(where_clause.scan(/(\w+)\s*(?:>|<|>=|<=|BETWEEN)/).flatten)
        # Extract columns from LIKE conditions
        columns.concat(where_clause.scan(/(\w+)\s*LIKE/).flatten)

        columns.reject { |col| reserved_word?(col) }.uniq
      end

      def extract_order_columns
        order_match = sql.match(/ORDER\s+BY\s+(.+?)(?:\s+LIMIT|\s*$)/i)
        return [] unless order_match

        order_clause = order_match[1]
        order_clause.split(",").map do |col|
          col.strip.gsub(/\s+(ASC|DESC)\s*$/i, "").strip
        end
      end

      def build_index_recommendation(table, columns, type, priority, reason, benefit)
        {
          type: type,
          table: table,
          columns: Array(columns),
          reason: reason,
          priority: priority,
          migration_code: generate_migration_code(table, columns),
          estimated_benefit: benefit,
          priority_score: calculate_priority_score(priority),
          execution_context: execution_context
        }
      end

      def build_fulltext_recommendation(table, column)
        {
          type: "full_text",
          table: table,
          columns: [ column ],
          reason: "LIKE with leading wildcard",
          priority: "low",
          migration_code: generate_fulltext_migration_code(table, [ column ]),
          estimated_benefit: "Full-text search instead of slow LIKE queries",
          priority_score: 30,
          execution_context: execution_context
        }
      end

      def prioritize_recommendations(recommendations)
        execution_frequency = operations.count

        recommendations.each do |rec|
          # Boost score based on execution frequency
          frequency_boost = [ execution_frequency * 2, 50 ].min
          rec[:priority_score] += frequency_boost
        end

        # Remove duplicates and sort by priority
        unique_recommendations = recommendations.uniq { |r| [ r[:table], r[:columns].sort ] }
        unique_recommendations.sort_by { |r| -r[:priority_score] }
      end

      def calculate_priority_score(priority)
        case priority
        when "high" then 100
        when "medium" then 60
        when "low" then 30
        else 50
        end
      end

      def execution_context
        @execution_context ||= {
          frequency: operations.count,
          frequency_description: describe_frequency(operations.count)
        }
      end

      def generate_migration_code(table_name, columns)
        columns = Array(columns)
        if columns.length == 1
          "add_index :#{table_name}, :#{columns.first}"
        else
          "add_index :#{table_name}, #{columns.inspect}"
        end
      end

      def generate_covering_migration_code(table_name, where_columns, select_columns)
        all_columns = (where_columns + select_columns).uniq
        "add_index :#{table_name}, #{all_columns.inspect}, name: 'covering_idx_#{table_name}_#{where_columns.join('_')}'"
      end

      def generate_fulltext_migration_code(table_name, columns)
        case database_adapter
        when "postgresql"
          "add_index :#{table_name}, :#{columns.first}, using: 'gin', opclass: 'gin_trgm_ops'"
        when "mysql", "mysql2"
          "add_index :#{table_name}, :#{columns.first}, type: 'fulltext'"
        else
          "# Full-text search not supported for #{database_adapter}"
        end
      end

      def describe_frequency(count)
        case count
        when 0..10 then "Low frequency"
        when 11..50 then "Medium frequency"
        when 51..100 then "High frequency"
        else "Very high frequency"
        end
      end

      def reserved_word?(word)
        word.upcase.in?([ "AND", "OR", "NOT", "NULL", "TRUE", "FALSE" ])
      end
    end
  end
end
