module RailsPulse
  class QueryAnalysisService
    def self.analyze_query(query_id)
      query = RailsPulse::Query.find(query_id)
      new(query).analyze
    end

    def initialize(query)
      @query = query
      @results = {
        analyzed_at: Time.current,
        explain_plan: nil,
        issues: [],
        metadata: {},
        query_stats: {},
        backtrace_analysis: {},
        suggestions: []
      }
    end

    def analyze
      # Get recent operations for actual SQL and backtraces
      recent_operations = fetch_recent_operations

      # Analyze query characteristics from normalized SQL
      @results[:query_stats] = analyze_query_characteristics(@query.normalized_sql)

      # Analyze backtraces from recent operations
      @results[:backtrace_analysis] = analyze_backtraces(recent_operations) if recent_operations.any?

      # Pattern-based issue detection on normalized SQL
      @results[:issues].concat(detect_pattern_issues(@query.normalized_sql))

      # EXPLAIN analysis if we have recent operations with actual SQL
      if recent_operations.any?
        actual_sql = recent_operations.first.label
        @results[:explain_plan] = generate_explain_plan(actual_sql)
        @results[:issues].concat(detect_explain_issues(@results[:explain_plan])) if @results[:explain_plan]
      end

      # Generate suggestions based on all analysis
      @results[:suggestions] = generate_suggestions

      # Save results to query
      save_results_to_query

      @results
    end

    private

    def fetch_recent_operations
      @query.operations
            .where("occurred_at > ?", 48.hours.ago)
            .order(occurred_at: :desc)
            .limit(50)
    end

    def analyze_query_characteristics(sql)
      {
        query_type: detect_query_type(sql),
        table_count: count_tables(sql),
        join_count: sql.scan(/\bJOIN\b/i).length,
        where_clause_complexity: analyze_where_complexity(sql),
        has_subqueries: sql.include?("(SELECT"),
        has_limit: sql.match?(/\bLIMIT\s+\d+/i),
        has_order_by: sql.include?("ORDER BY"),
        has_group_by: sql.include?("GROUP BY"),
        has_having: sql.include?("HAVING"),
        has_distinct: sql.include?("DISTINCT"),
        has_aggregations: has_aggregations?(sql),
        estimated_complexity: calculate_complexity_score(sql)
      }
    end

    def analyze_backtraces(operations)
      backtraces = operations.filter_map(&:codebase_location).compact

      {
        total_executions: operations.count,
        unique_locations: backtraces.uniq.count,
        most_common_location: find_most_common_location(backtraces),
        potential_n_plus_one: detect_n_plus_one_pattern(operations),
        execution_frequency: calculate_execution_frequency(operations),
        location_distribution: calculate_location_distribution(backtraces)
      }
    end

    def detect_pattern_issues(sql)
      issues = []

      # Missing WHERE clause on SELECT
      if sql.match?(/^SELECT.*FROM.*(?!WHERE)/i) && !sql.include?("LIMIT")
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
      if sql.match?(/^SELECT.*FROM.*WHERE/i) && !sql.include?("LIMIT") && !sql.include?("COUNT")
        issues << {
          type: "missing_limit",
          severity: "warning",
          description: "Query may return large result sets without LIMIT",
          impact: "Memory exhaustion and slow response times"
        }
      end

      # Complex WHERE clauses
      where_conditions = sql.scan(/WHERE\s+(.+?)(?:\s+ORDER\s+BY|\s+GROUP\s+BY|\s+LIMIT|\s*$)/i).flatten.first
      if where_conditions && where_conditions.scan(/\bAND\b|\bOR\b/i).length > 5
        issues << {
          type: "complex_where_clause",
          severity: "warning",
          description: "Complex WHERE clause with many conditions",
          impact: "Difficult to optimize and maintain"
        }
      end

      issues
    end

    def generate_explain_plan(sql)
      return nil unless sql.present?

      begin
        # Sanitize and prepare SQL for EXPLAIN
        sanitized_sql = sanitize_sql_for_explain(sql)

        # Execute EXPLAIN with timeout
        Timeout.timeout(5.seconds) do
          case RailsPulse::ApplicationRecord.connection.adapter_name.downcase
          when "postgresql"
            execute_postgres_explain(sanitized_sql)
          when "mysql", "mysql2"
            execute_mysql_explain(sanitized_sql)
          when "sqlite"
            execute_sqlite_explain(sanitized_sql)
          else
            nil
          end
        end
      rescue => e
        Rails.logger.warn("[QueryAnalysis] EXPLAIN failed for query #{@query.id}: #{e.message}")
        nil
      end
    end

    def detect_explain_issues(explain_plan)
      return [] unless explain_plan.present?

      issues = []

      # Look for common issues in EXPLAIN output
      if explain_plan.downcase.include?("seq scan") || explain_plan.downcase.include?("table scan")
        issues << {
          type: "sequential_scan",
          severity: "warning",
          description: "Query performs sequential/table scan",
          impact: "Poor performance on large tables"
        }
      end

      if explain_plan.downcase.include?("temporary") || explain_plan.downcase.include?("filesort")
        issues << {
          type: "temporary_table",
          severity: "warning",
          description: "Query uses temporary tables or filesort",
          impact: "Increased memory usage and processing time"
        }
      end

      issues
    end

    def generate_suggestions
      suggestions = []

      # Suggestions based on issues
      @results[:issues].each do |issue|
        case issue[:type]
        when "select_star"
          suggestions << {
            type: "optimization",
            action: "Specify only needed columns instead of SELECT *",
            benefit: "Reduced memory usage and faster data transfer"
          }
        when "missing_limit"
          suggestions << {
            type: "optimization",
            action: "Add LIMIT clause to prevent large result sets",
            benefit: "Controlled memory usage and faster response times"
          }
        when "sequential_scan"
          suggestions << {
            type: "index",
            action: "Consider adding database indexes for WHERE clause columns",
            benefit: "Dramatically faster query execution"
          }
        end
      end

      # Suggestions based on query characteristics
      stats = @results[:query_stats]

      if stats[:join_count] > 3
        suggestions << {
          type: "optimization",
          action: "Review if all JOINs are necessary",
          benefit: "Simplified query execution and better performance"
        }
      end

      if stats[:estimated_complexity] > 10
        suggestions << {
          type: "refactoring",
          action: "Consider breaking complex query into smaller parts",
          benefit: "Easier maintenance and potentially better performance"
        }
      end

      suggestions
    end

    def save_results_to_query
      @query.update!(
        analyzed_at: @results[:analyzed_at],
        explain_plan: @results[:explain_plan],
        issues: @results[:issues],
        metadata: @results[:metadata],
        query_stats: @results[:query_stats],
        backtrace_analysis: @results[:backtrace_analysis],
        suggestions: @results[:suggestions]
      )
    end

    # Helper methods for analysis

    def detect_query_type(sql)
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

    def count_tables(sql)
      # Simple table counting - look for FROM and JOIN clauses
      tables = []
      tables.concat(sql.scan(/FROM\s+(\w+)/i).flatten)
      tables.concat(sql.scan(/JOIN\s+(\w+)/i).flatten)
      tables.uniq.length
    end

    def analyze_where_complexity(sql)
      where_match = sql.match(/WHERE\s+(.+?)(?:\s+ORDER\s+BY|\s+GROUP\s+BY|\s+LIMIT|\s*$)/i)
      return 0 unless where_match

      where_clause = where_match[1]
      condition_count = where_clause.scan(/\bAND\b|\bOR\b/i).length + 1
      function_count = where_clause.scan(/\w+\s*\(/).length

      condition_count + (function_count * 2)
    end

    def has_aggregations?(sql)
      sql.match?(/\b(COUNT|SUM|AVG|MIN|MAX|GROUP_CONCAT)\s*\(/i)
    end

    def calculate_complexity_score(sql)
      score = 0
      score += count_tables(sql) * 2
      score += sql.scan(/\bJOIN\b/i).length * 3
      score += analyze_where_complexity(sql)
      score += sql.scan(/\bUNION\b/i).length * 4
      score += sql.scan(/\(SELECT/i).length * 5
      score
    end

    def find_most_common_location(backtraces)
      return nil if backtraces.empty?

      frequency = backtraces.tally
      frequency.max_by { |_, count| count }&.first
    end

    def detect_n_plus_one_pattern(operations)
      # Simple N+1 detection: many operations with same query in short time
      time_window = 1.minute
      groups = operations.group_by { |op| op.occurred_at.beginning_of_minute }

      groups.any? { |_, ops| ops.count > 10 }
    end

    def calculate_execution_frequency(operations)
      return 0 if operations.empty?

      time_span = operations.last.occurred_at - operations.first.occurred_at
      return operations.count if time_span <= 0

      (operations.count / time_span.in_hours).round(2)
    end

    def calculate_location_distribution(backtraces)
      return {} if backtraces.empty?

      total = backtraces.length
      backtraces.tally.transform_values { |count| (count.to_f / total * 100).round(1) }
    end

    def sanitize_sql_for_explain(sql)
      # Basic sanitization for EXPLAIN
      sql.strip.gsub(/;+\s*$/, "")
    end

    def execute_postgres_explain(sql)
      result = RailsPulse::ApplicationRecord.connection.execute("EXPLAIN (ANALYZE, BUFFERS) #{sql}")
      result.values.flatten.join("\n")
    end

    def execute_mysql_explain(sql)
      result = RailsPulse::ApplicationRecord.connection.execute("EXPLAIN #{sql}")
      result.to_a.map { |row| row.values.join(" | ") }.join("\n")
    end

    def execute_sqlite_explain(sql)
      result = RailsPulse::ApplicationRecord.connection.execute("EXPLAIN QUERY PLAN #{sql}")
      result.map { |row| row.values.join(" | ") }.join("\n")
    end
  end
end
