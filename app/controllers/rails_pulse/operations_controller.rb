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
      OperationSuggestions.for(@operation, parent: @parent)
    end
  end
end
