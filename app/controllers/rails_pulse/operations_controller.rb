module RailsPulse
  class OperationsController < ApplicationController
    before_action :set_operation, only: :show

    def show
      @request = @operation.request
      @job_run = @operation.job_run
      @parent = @request || @job_run
      @related_operations = find_related_operations
      @performance_context = calculate_performance_context
      @optimization_suggestions = generate_optimization_suggestions

      respond_to do |format|
        format.html
      end
    end

    private

    def set_operation
      @operation = Operation.find(params[:id])
    end

    def find_related_operations
      return [] unless @parent

      case @operation.operation_type
      when "sql"
        # Find other SQL operations in the same request/job run with similar queries
        @parent.operations
          .where(operation_type: [ "sql" ])
          .where.not(id: @operation.id)
          .limit(5)
      when "template", "partial", "layout", "collection"
        # Find other view operations in the same request/job run
        @parent.operations
          .where(operation_type: [ "template", "partial", "layout", "collection" ])
          .where.not(id: @operation.id)
          .limit(5)
      else
        # Find operations of the same type in the same request/job run
        @parent.operations
          .where(operation_type: @operation.operation_type)
          .where.not(id: @operation.id)
          .limit(5)
      end
    end

    def calculate_performance_context
      # Calculate percentiles and comparisons for this operation type
      similar_operations = Operation.where(operation_type: @operation.operation_type)
        .where("occurred_at >= ?", 7.days.ago)
        .limit(1000)

      return {} if similar_operations.empty?

      durations = similar_operations.pluck(:duration).sort
      total_count = durations.length

      {
        percentile_50: durations[(total_count * 0.5).floor] || 0,
        percentile_75: durations[(total_count * 0.75).floor] || 0,
        percentile_90: durations[(total_count * 0.9).floor] || 0,
        percentile_95: durations[(total_count * 0.95).floor] || 0,
        average: durations.sum / total_count.to_f,
        count: total_count,
        current_percentile: calculate_percentile(@operation.duration, durations)
      }
    end

    def calculate_percentile(value, sorted_array)
      return 0 if sorted_array.empty?

      index = sorted_array.bsearch_index { |x| x >= value } || sorted_array.length
      (index.to_f / sorted_array.length * 100).round(1)
    end

    def generate_optimization_suggestions
      suggestions = []

      case @operation.operation_type
      when "sql"
        suggestions.concat(sql_optimization_suggestions)
      when "template", "partial", "layout", "collection"
        suggestions.concat(view_optimization_suggestions)
      when "controller"
        suggestions.concat(controller_optimization_suggestions)
      when "cache_read", "cache_write"
        suggestions.concat(cache_optimization_suggestions)
      when "http"
        suggestions.concat(http_optimization_suggestions)
      end

      suggestions
    end

    def sql_optimization_suggestions
      suggestions = []

      if @operation.duration > 100
        suggestions << {
          type: "performance",
          icon: "zap",
          title: "Slow Query Detected",
          description: "This query took #{@operation.duration.round(2)}ms. Consider adding database indexes or optimizing the query.",
          priority: "high"
        }
      end

      if @operation.label&.match?(/SELECT.*FROM\s+(\w+)/i)
        table_name = @operation.label.match(/FROM\s+(\w+)/i)&.captures&.first
        if table_name
          suggestions << {
            type: "index",
            icon: "database",
            title: "Index Optimization",
            description: "Review indexes on the '#{table_name}' table. Consider composite indexes for WHERE clauses.",
            priority: "medium"
          }
        end
      end

      # Check for potential N+1 queries
      if @parent
        similar_queries = @parent.operations
          .where(operation_type: [ "sql" ])
          .where("label LIKE ?", "%#{@operation.label.split.first(3).join(' ')}%")
          .where.not(id: @operation.id)

        if similar_queries.count > 2
          suggestions << {
            type: "n_plus_one",
            icon: "alert-triangle",
            title: "Potential N+1 Query",
            description: "#{similar_queries.count + 1} similar queries detected. Consider using includes() or joins().",
            priority: "high"
          }
        end
      end

      suggestions
    end

    def view_optimization_suggestions
      suggestions = []

      if @operation.duration > 100
        suggestions << {
          type: "performance",
          icon: "zap",
          title: "Slow View Rendering",
          description: "This view took #{@operation.duration.round(2)}ms to render. Consider fragment caching or reducing database calls.",
          priority: "high"
        }
      end

      # Check for database queries in views
      if @parent
        view_db_operations = @parent.operations
          .where(operation_type: [ "sql" ])
          .where("occurred_at >= ? AND occurred_at <= ?",
                 @operation.occurred_at,
                 @operation.occurred_at + @operation.duration)

        if view_db_operations.count > 0
          suggestions << {
            type: "database",
            icon: "database",
            title: "Database Queries in View",
            description: "#{view_db_operations.count} database queries during view rendering. Move data fetching to the controller.",
            priority: "medium"
          }
        end
      end

      suggestions
    end

    def controller_optimization_suggestions
      suggestions = []

      if @operation.duration > 500
        suggestions << {
          type: "performance",
          icon: "zap",
          title: "Slow Controller Action",
          description: "This action took #{@operation.duration.round(2)}ms. Consider moving heavy computation to background jobs.",
          priority: "high"
        }
      end

      suggestions
    end

    def cache_optimization_suggestions
      suggestions = []

      if @operation.operation_type == "cache_read" && @operation.duration > 10
        suggestions << {
          type: "performance",
          icon: "clock",
          title: "Slow Cache Read",
          description: "Cache read took #{@operation.duration.round(2)}ms. Check cache backend performance.",
          priority: "medium"
        }
      end

      suggestions
    end

    def http_optimization_suggestions
      suggestions = []

      if @operation.duration > 1000
        suggestions << {
          type: "performance",
          icon: "globe",
          title: "Slow External Request",
          description: "HTTP request took #{@operation.duration.round(2)}ms. Consider caching responses or using background jobs.",
          priority: "high"
        }
      end

      suggestions
    end
  end
end
