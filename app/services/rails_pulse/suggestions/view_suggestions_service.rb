module RailsPulse
  module Suggestions
    class ViewSuggestionsService < Base
      def generate
        suggestions = []

        if operation.duration > 100
          suggestions << build_suggestion(
            type: "performance",
            icon: "zap",
            title: "Slow View Rendering",
            description: "This view took #{operation.duration.round(2)}ms to render. Consider fragment caching or reducing database calls.",
            priority: "high"
          )
        end

        # Check for database queries in views
        if parent
          view_db_operations = parent.operations
            .where(operation_type: [ "sql" ])
            .where("occurred_at >= ? AND occurred_at <= ?",
                   operation.occurred_at,
                   operation.occurred_at + operation.duration)

          if view_db_operations.count > 0
            suggestions << build_suggestion(
              type: "database",
              icon: "database",
              title: "Database Queries in View",
              description: "#{view_db_operations.count} database queries during view rendering. Move data fetching to the controller.",
              priority: "medium"
            )
          end
        end

        suggestions
      end
    end
  end
end
