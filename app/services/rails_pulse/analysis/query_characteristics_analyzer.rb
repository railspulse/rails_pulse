# Analyzes SQL query structure and complexity.
# Detects query type, table joins, WHERE complexity, and common anti-patterns like SELECT * or missing LIMIT.
module RailsPulse
  module Analysis
    class QueryCharacteristicsAnalyzer < BaseAnalyzer
      def analyze
        {
          query_type: detect_query_type,
          table_count: count_tables,
          join_count: count_joins,
          where_clause_complexity: analyze_where_complexity,
          has_subqueries: has_subqueries?,
          has_limit: has_limit?,
          has_order_by: has_order_by?,
          has_group_by: has_group_by?,
          has_having: has_having?,
          has_distinct: has_distinct?,
          has_aggregations: has_aggregations?,
          estimated_complexity: calculate_complexity_score,
          pattern_issues: detect_pattern_issues
        }
      end

      private

      def detect_query_type
        case sql.strip.upcase
        when /^SELECT/ then "SELECT"
        when /^INSERT/ then "INSERT"
        when /^UPDATE/ then "UPDATE"
        when /^DELETE/ then "DELETE"
        when /^CREATE/ then "CREATE"
        when /^DROP/ then "DROP"
        when /^ALTER/ then "ALTER"
        else "UNKNOWN"
        end
      end

      def count_tables
        tables = []
        tables.concat(sql.scan(/FROM\s+(\w+)/i).flatten)
        tables.concat(sql.scan(/JOIN\s+(\w+)/i).flatten)
        tables.uniq.length
      end

      def count_joins
        sql.scan(/\bJOIN\b/i).length
      end

      def analyze_where_complexity
        where_clause = extract_where_clause
        return 0 unless where_clause

        condition_count = where_clause.scan(/\bAND\b|\bOR\b/i).length + 1
        function_count = where_clause.scan(/\w+\s*\(/).length

        condition_count + (function_count * 2)
      end

      def has_subqueries?
        sql.include?("(SELECT")
      end

      def has_limit?
        sql.match?(/\bLIMIT\s+\d+/i)
      end

      def has_order_by?
        sql.include?("ORDER BY")
      end

      def has_group_by?
        sql.include?("GROUP BY")
      end

      def has_having?
        sql.include?("HAVING")
      end

      def has_distinct?
        sql.include?("DISTINCT")
      end

      def has_aggregations?
        sql.match?(/\b(COUNT|SUM|AVG|MIN|MAX|GROUP_CONCAT)\s*\(/i)
      end

      def calculate_complexity_score
        score = 0
        score += count_tables * 2
        score += count_joins * 3
        score += analyze_where_complexity
        score += sql.scan(/\bUNION\b/i).length * 4
        score += sql.scan(/\(SELECT/i).length * 5
        score
      end

      def detect_pattern_issues
        issues = []

        # Missing WHERE clause on SELECT
        if sql.match?(/^SELECT.*FROM.*(?!WHERE)/i) && !has_limit?
          issues << {
            type: "missing_where_clause",
            severity: "warning",
            description: "SELECT query without WHERE clause may return excessive data",
            impact: "Performance degradation from full table scans"
          }
        end

        # SELECT * usage
        if sql.include?("SELECT *")
          issues << {
            type: "select_star",
            severity: "info",
            description: "Using SELECT * may retrieve unnecessary columns",
            impact: "Increased memory usage and network transfer"
          }
        end

        # Missing LIMIT on potentially large results
        if sql.match?(/^SELECT.*FROM.*WHERE/i) && !has_limit? && !sql.include?("COUNT")
          issues << {
            type: "missing_limit",
            severity: "warning",
            description: "Query may return large result sets without LIMIT",
            impact: "Memory exhaustion and slow response times"
          }
        end

        # Complex WHERE clauses
        where_clause = extract_where_clause
        if where_clause && where_clause.scan(/\bAND\b|\bOR\b/i).length > 5
          issues << {
            type: "complex_where_clause",
            severity: "warning",
            description: "Complex WHERE clause with many conditions",
            impact: "Difficult to optimize and maintain"
          }
        end

        issues
      end
    end
  end
end
