module RailsPulse
  class OperationSuggestions
    VIEW_TYPES = %w[template partial layout collection].freeze

    def self.for(operation, parent: nil)
      new(operation, parent).generate
    end

    def initialize(operation, parent)
      @operation = operation
      @parent = parent
    end

    def generate
      case @operation.operation_type
      when "sql"       then sql_suggestions
      when *VIEW_TYPES then view_suggestions
      when "controller" then controller_suggestions
      when "cache_read" then cache_suggestions
      when "http"       then http_suggestions
      else []
      end
    end

    private

    attr_reader :operation, :parent

    def sql_suggestions
      result = []

      # Surface stored deep-analysis suggestions (from QueryAnalysisService)
      if operation.query&.suggestions&.any?
        operation.query.suggestions.each { |s| result << adapt_analysis_suggestion(s) }
      end

      if operation.duration > 100
        result << build(
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
          result << build(
            type: "index",
            icon: "database",
            title: "Index Optimization",
            description: "Review indexes on the '#{table_name}' table. Consider composite indexes for WHERE clauses.",
            priority: "medium"
          )
        end
      end

      if parent && operation.query_id.present?
        similar_count = parent.operations
          .where(operation_type: "sql", query_id: operation.query_id)
          .where.not(id: operation.id)
          .count

        if similar_count > 2
          result << build(
            type: "n_plus_one",
            icon: "alert-triangle",
            title: "Potential N+1 Query",
            description: "#{similar_count + 1} similar queries detected. Consider using includes() or joins().",
            priority: "high"
          )
        end
      end

      deduplicate(result)
    end

    def view_suggestions
      result = []

      if operation.duration > 100
        result << build(
          type: "performance",
          icon: "zap",
          title: "Slow View Rendering",
          description: "This view took #{operation.duration.round(2)}ms to render. Consider fragment caching or reducing database calls.",
          priority: "high"
        )
      end

      if parent
        view_db_count = parent.operations
          .where(operation_type: "sql")
          .where("occurred_at >= ? AND occurred_at <= ?",
                 operation.occurred_at,
                 operation.occurred_at + operation.duration)
          .count

        if view_db_count > 0
          result << build(
            type: "database",
            icon: "database",
            title: "Database Queries in View",
            description: "#{view_db_count} database queries during view rendering. Move data fetching to the controller.",
            priority: "medium"
          )
        end
      end

      result
    end

    def controller_suggestions
      return [] unless operation.duration > 500

      [ build(
        type: "performance",
        icon: "zap",
        title: "Slow Controller Action",
        description: "This action took #{operation.duration.round(2)}ms. Consider moving heavy computation to background jobs.",
        priority: "high"
      ) ]
    end

    def cache_suggestions
      return [] unless operation.duration > 10

      [ build(
        type: "performance",
        icon: "clock",
        title: "Slow Cache Read",
        description: "Cache read took #{operation.duration.round(2)}ms. Check cache backend performance.",
        priority: "medium"
      ) ]
    end

    def http_suggestions
      return [] unless operation.duration > 1000

      [ build(
        type: "performance",
        icon: "globe",
        title: "Slow External Request",
        description: "HTTP request took #{operation.duration.round(2)}ms. Consider caching responses or using background jobs.",
        priority: "high"
      ) ]
    end

    def adapt_analysis_suggestion(suggestion)
      build(
        type: suggestion[:type] || suggestion["type"],
        icon: icon_for_analysis_suggestion(suggestion),
        title: suggestion[:action] || suggestion["action"],
        description: suggestion[:benefit] || suggestion["benefit"],
        priority: suggestion[:priority] || suggestion["priority"]
      )
    end

    def icon_for_analysis_suggestion(suggestion)
      category = suggestion[:category] || suggestion["category"]
      type = suggestion[:type] || suggestion["type"]

      case category || type
      when "database_optimization", "index" then "database"
      when "performance_critical", "n_plus_one" then "alert-triangle"
      else "zap"
      end
    end

    def build(type:, icon:, title:, description:, priority:)
      { type: type, icon: icon, title: title, description: description, priority: priority }
    end

    def deduplicate(suggestions)
      suggestions.uniq { |s| s[:title] }
    end
  end
end
