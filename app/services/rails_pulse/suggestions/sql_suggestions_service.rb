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

        if operation.label&.match?(/SELECT.*FROM\s+(\w+)/i)
          table_name = operation.label.match(/FROM\s+(\w+)/i)&.captures&.first
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

        # Check for potential N+1 queries
        if parent
          # Sanitize LIKE pattern to prevent SQL injection via wildcards
          label_prefix = operation.label.split.first(3).join(" ")
          sanitized_pattern = ActiveRecord::Base.sanitize_sql_like(label_prefix)

          similar_queries = parent.operations
            .where(operation_type: [ "sql" ])
            .where("label LIKE ?", "%#{sanitized_pattern}%")
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
