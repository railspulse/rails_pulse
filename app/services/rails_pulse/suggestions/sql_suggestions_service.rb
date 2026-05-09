module RailsPulse
  module Suggestions
    class SqlSuggestionsService < Base
      def generate
        suggestions = []

        if operation.duration > 100
          suggestions << build_suggestion(
            type: "performance",
            icon: "zap",
            title: "Slow Query Detected",
            description: "This query took #{operation.duration.round(2)}ms. Consider adding database indexes or optimizing the query.",
            priority: "high"
          )
        end

        sql_source = operation.actual_sql.presence || operation.query&.normalized_sql
        if sql_source&.match?(/SELECT.*FROM\s+(\w+)/i)
          table_name = sql_source.match(/FROM\s+(\w+)/i)&.captures&.first
          if table_name
            suggestions << build_suggestion(
              type: "index",
              icon: "database",
              title: "Index Optimization",
              description: "Review indexes on the '#{table_name}' table. Consider composite indexes for WHERE clauses.",
              priority: "medium"
            )
          end
        end

        # Check for potential N+1 queries by matching on query_id (same normalized SQL pattern)
        if parent && operation.query_id.present?
          similar_queries = parent.operations
            .where(operation_type: "sql", query_id: operation.query_id)
            .where.not(id: operation.id)

          if similar_queries.count > 2
            suggestions << build_suggestion(
              type: "n_plus_one",
              icon: "alert-triangle",
              title: "Potential N+1 Query",
              description: "#{similar_queries.count + 1} similar queries detected. Consider using includes() or joins().",
              priority: "high"
            )
          end
        end

        suggestions
      end
    end
  end
end
