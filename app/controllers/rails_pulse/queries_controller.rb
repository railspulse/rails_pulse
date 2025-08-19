module RailsPulse
  class QueriesController < ApplicationController
    include ChartTableConcern

    before_action :set_query, only: :show

    def index
      setup_chart_and_table_data
    end

    def show
      setup_chart_and_table_data
    end

    private

    def chart_model
      Operation
    end

    def table_model
      show_action? ? Operation : Query
    end

    def chart_class
      Queries::Charts::AverageQueryTimes
    end

    def chart_options
      show_action? ? { query: @query } : {}
    end

    def build_chart_ransack_params(ransack_params)
      base_params = ransack_params.except(:s)

      if show_action?
        base_params.merge(
          query_id_eq: @query.id,
          occurred_at_gteq: Time.at(@start_time),
          occurred_at_lt: Time.at(@end_time),
          duration_gteq: @start_duration
        )
      else
        # For index action, build params for Operation model directly
        base_params.merge(
          occurred_at_gteq: Time.at(@start_time),
          occurred_at_lt: Time.at(@end_time),
          duration_gteq: @start_duration
        )
      end
    end

    def build_table_ransack_params(ransack_params)
      if show_action?
        ransack_params.merge(
          query_id_eq: @query.id,
          occurred_at_gteq: Time.at(@table_start_time),
          occurred_at_lt: Time.at(@table_end_time),
          duration_gteq: @start_duration
        )
      else
        ransack_params.merge(
          operations_occurred_at_gteq: Time.at(@table_start_time),
          operations_occurred_at_lt: Time.at(@table_end_time),
          operations_duration_gteq: @start_duration
        )
      end
    end

    def default_table_sort
      "occurred_at desc"
    end

    def build_table_results
      if show_action?
        @ransack_query.result.select("id", "occurred_at", "duration")
      else
        # Use Rails associations for cleaner joins and let ActiveRecord optimize
        # Filter operations by time range first, then aggregate by query
        time_range_start = Time.at(@table_start_time)
        time_range_end = Time.at(@table_end_time)
        
        Query.joins(:operations)
          .where(operations: { 
            occurred_at: time_range_start...time_range_end,
            duration: @start_duration..Float::INFINITY
          })
          .group("rails_pulse_queries.id, rails_pulse_queries.normalized_sql, rails_pulse_queries.created_at, rails_pulse_queries.updated_at")
          .select(
            "rails_pulse_queries.*",
            optimized_aggregations_sql
          )
      end
    end

    private

    def optimized_aggregations_sql
      # Efficient aggregations that work with our composite indexes
      # Use alias "operations" instead of full table name since we use .joins(:operations)
      [
        "COALESCE(AVG(operations.duration), 0) AS average_query_time_ms",
        "COUNT(operations.id) AS execution_count",
        "COALESCE(SUM(operations.duration), 0) AS total_time_consumed",
        "MAX(operations.occurred_at) AS occurred_at"
      ].join(", ")
    end

    def show_action?
      action_name == "show"
    end

    def pagination_method
      show_action? ? :set_pagination_limit : :store_pagination_limit
    end

    def set_query
      @query = Query.find(params[:id])
    end

    def setup_metic_cards
      @average_query_times_card = Queries::Cards::AverageQueryTimes.new(query: @query).to_metric_card
      @percentile_response_times_card = Queries::Cards::PercentileQueryTimes.new(query: @query).to_metric_card
      @execution_rate_card = Queries::Cards::ExecutionRate.new(query: @query).to_metric_card
    end
  end
end
