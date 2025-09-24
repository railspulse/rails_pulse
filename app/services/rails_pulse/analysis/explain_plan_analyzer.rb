# Executes database EXPLAIN commands and analyzes query execution plans.
# Detects sequential scans, temporary tables, high-cost operations, and database-specific performance issues.
module RailsPulse
  module Analysis
    class ExplainPlanAnalyzer < BaseAnalyzer
      EXPLAIN_TIMEOUT = 5.seconds

      def analyze
        return { explain_plan: nil, issues: [] } if recent_operations.empty?

        actual_sql = recent_operations.first.label
        explain_plan = generate_explain_plan(actual_sql)

        {
          explain_plan: explain_plan,
          issues: detect_explain_issues(explain_plan)
        }
      end

      private

      def generate_explain_plan(sql)
        return nil unless sql.present?

        # Skip EXPLAIN queries in test environment to avoid transaction issues
        return nil if Rails.env.test?

        begin
          sanitized_sql = sanitize_sql_for_explain(sql)

          Timeout.timeout(EXPLAIN_TIMEOUT) do
            case database_adapter
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
          Rails.logger.warn("[ExplainPlanAnalyzer] EXPLAIN failed for query #{query.id}: #{e.message}")
          nil
        end
      end

      def detect_explain_issues(explain_plan)
        return [] unless explain_plan.present?

        issues = []

        # Look for common issues in EXPLAIN output
        if sequential_scan?(explain_plan)
          issues << {
            type: "sequential_scan",
            severity: "warning",
            description: "Query performs sequential/table scan",
            impact: "Poor performance on large tables"
          }
        end

        if temporary_operations?(explain_plan)
          issues << {
            type: "temporary_table",
            severity: "warning",
            description: "Query uses temporary tables or filesort",
            impact: "Increased memory usage and processing time"
          }
        end

        # Database-specific analysis
        case database_adapter
        when "postgresql"
          issues.concat(analyze_postgres_specific_issues(explain_plan))
        when "mysql", "mysql2"
          issues.concat(analyze_mysql_specific_issues(explain_plan))
        when "sqlite"
          issues.concat(analyze_sqlite_specific_issues(explain_plan))
        end

        issues
      end

      def sequential_scan?(explain_plan)
        explain_plan.downcase.include?("seq scan") ||
        explain_plan.downcase.include?("table scan") ||
        explain_plan.downcase.include?("full table scan")
      end

      def temporary_operations?(explain_plan)
        explain_plan.downcase.include?("temporary") ||
        explain_plan.downcase.include?("filesort") ||
        explain_plan.downcase.include?("using temporary")
      end

      def analyze_postgres_specific_issues(explain_plan)
        issues = []

        # High cost operations
        if explain_plan.match(/cost=(\d+\.\d+)\.\.(\d+\.\d+)/)
          total_cost = $2.to_f
          if total_cost > 1000
            issues << {
              type: "high_cost_operation",
              severity: "warning",
              description: "Query has high execution cost (#{total_cost.round(2)})",
              impact: "May indicate need for optimization or indexing"
            }
          end
        end

        # Hash joins on large datasets
        if explain_plan.include?("Hash Join") && explain_plan.match(/rows=(\d+)/)
          rows = $1.to_i
          if rows > 10000
            issues << {
              type: "large_hash_join",
              severity: "info",
              description: "Hash join on large dataset (#{rows} rows)",
              impact: "High memory usage during query execution"
            }
          end
        end

        issues
      end

      def analyze_mysql_specific_issues(explain_plan)
        issues = []

        # Using where with no index
        if explain_plan.include?("Using where") && !explain_plan.include?("Using index")
          issues << {
            type: "where_without_index",
            severity: "warning",
            description: "WHERE clause not using index efficiently",
            impact: "Slower query execution due to row-by-row filtering"
          }
        end

        # Full table scan with large row count
        if explain_plan.match(/type: ALL.*rows: (\d+)/)
          rows = $1.to_i
          if rows > 1000
            issues << {
              type: "full_scan_large_table",
              severity: "warning",
              description: "Full table scan on table with #{rows} rows",
              impact: "Very slow query execution on large dataset"
            }
          end
        end

        issues
      end

      def analyze_sqlite_specific_issues(explain_plan)
        issues = []

        # SCAN TABLE operations
        if explain_plan.include?("SCAN TABLE")
          issues << {
            type: "table_scan",
            severity: "warning",
            description: "SQLite performing table scan",
            impact: "Linear search through all table rows"
          }
        end

        # Missing index usage
        if explain_plan.include?("USING INDEX") == false && explain_plan.include?("WHERE")
          issues << {
            type: "no_index_usage",
            severity: "info",
            description: "Query not utilizing available indexes",
            impact: "Potential for optimization with proper indexing"
          }
        end

        issues
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
end
