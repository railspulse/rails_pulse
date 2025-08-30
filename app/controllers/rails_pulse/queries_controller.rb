module RailsPulse
  class QueriesController < ApplicationController
    include ChartTableConcern

    before_action :set_query, only: :show

    def index
      @average_query_times_metric_card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: @query).to_metric_card
      @percentile_query_times_metric_card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: @query).to_metric_card
      @execution_rate_metric_card = RailsPulse::Queries::Cards::ExecutionRate.new(query: @query).to_metric_card

      setup_chart_and_table_data
    end

    def show
      @average_query_times_metric_card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: @query).to_metric_card
      @percentile_query_times_metric_card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: @query).to_metric_card
      @execution_rate_metric_card = RailsPulse::Queries::Cards::ExecutionRate.new(query: @query).to_metric_card

      setup_chart_and_table_data
    end

    private

    def chart_model
      Summary
    end

    def table_model
      show_action? ? Operation : Summary
    end

    def chart_class
      Queries::Charts::AverageQueryTimes
    end

    def chart_options
      show_action? ? { query: @query } : {}
    end

    def build_chart_ransack_params(ransack_params)
      base_params = ransack_params.except(:s).merge(
        period_start_gteq: Time.at(@start_time),
        period_start_lt: Time.at(@end_time)
      )

      # Only add duration filter if we have a meaningful threshold
      base_params[:avg_duration_gteq] = @start_duration if @start_duration && @start_duration > 0

      if show_action?
        base_params.merge(summarizable_id_eq: @query.id)
      else
        base_params
      end
    end

    def build_table_ransack_params(ransack_params)
      if show_action?
        # For Operation model on show page
        params = ransack_params.merge(
          occurred_at_gteq: Time.at(@table_start_time),
          occurred_at_lt: Time.at(@table_end_time),
          query_id_eq: @query.id
        )
        params[:duration_gteq] = @start_duration if @start_duration && @start_duration > 0
        params
      else
        # For Summary model on index page
        params = ransack_params.merge(
          period_start_gteq: Time.at(@table_start_time),
          period_start_lt: Time.at(@table_end_time)
        )
        params[:avg_duration_gteq] = @start_duration if @start_duration && @start_duration > 0
        params
      end
    end

    def default_table_sort
      show_action? ? "occurred_at desc" : "period_start desc"
    end

    def build_table_results
      if show_action?
        @ransack_query.result
      else
        Queries::Tables::Index.new(
          ransack_query: @ransack_query,
          period_type: period_type,
          start_time: @start_time,
          params: params
        ).to_table
      end
    end

    private

    def show_action?
      action_name == "show"
    end

    def pagination_method
      show_action? ? :set_pagination_limit : :store_pagination_limit
    end

    def setup_table_data(ransack_params)
      table_ransack_params = build_table_ransack_params(ransack_params)
      @ransack_query = table_model.ransack(table_ransack_params)

      # Only apply default sort if not using Queries::Tables::Index (which handles its own sorting)
      if show_action?
        @ransack_query.sorts = default_table_sort if @ransack_query.sorts.empty?
      end

      table_results = build_table_results
      handle_pagination

      @pagy, @table_data = pagy(table_results, limit: session_pagination_limit)
    end

    def handle_pagination
      method = pagination_method
      send(method, params[:limit]) if params[:limit].present?
    end

    def setup_time_and_response_ranges
      @start_time, @end_time, @selected_time_range, @time_diff_hours = setup_time_range
      @start_duration, @selected_response_range = setup_duration_range(:query)
    end

    def set_query
      @query = Query.find(params[:id])
    end
  end
end
