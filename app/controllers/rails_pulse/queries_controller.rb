module RailsPulse
  class QueriesController < ApplicationController
    include Pagy::Backend
    include TimeRangeConcern
    include ResponseRangeConcern

    before_action :setup_time_and_response_ranges
    before_action :set_query, only: :show

    def index
      ransack_params = params[:q] || {}
      ransack_params.merge!(
        operations_occurred_at_gteq: @start_time,
        operations_occurred_at_lt: @end_time,
        operations_duration_gteq: @start_duration
      )
      @ransack_query = Query.ransack(ransack_params)

      # Set default sort if no sort is specified
      @ransack_query.sorts = "occurred_at desc" if @ransack_query.sorts.empty?

      unless turbo_frame_request?
        # setup_metic_cards
        setup_chart_formatters
        @chart_data = Queries::Charts::AverageQueryTimes.new(
          ransack_query: @ransack_query,
          group_by: group_by
        ).to_rails_chart
      end

      table_results = @ransack_query.result(distinct: false)
        .includes(:operations)
        .left_joins(:operations)
        .group("rails_pulse_queries.id")
        .select(
          "rails_pulse_queries.*",
          "COALESCE(AVG(rails_pulse_operations.duration), 0) AS average_query_time_ms",
          "COUNT(rails_pulse_operations.id) AS execution_count",
          "COALESCE(SUM(rails_pulse_operations.duration), 0) AS total_time_consumed",
          "MAX(rails_pulse_operations.occurred_at) AS occurred_at"
        )
      store_pagination_limit(params[:limit]) if params[:limit].present?
      @pagy, @table_data = pagy(table_results, limit: session_pagination_limit)
    end

    def show
      ransack_params = params[:q] || {}
      ransack_params.merge!(
        query_id_eq: @query.id,
        occurred_at_gteq: @start_time,
        occurred_at_lt: @end_time,
        duration_gteq: @start_duration
      )
      @ransack_query = Operation.ransack(ransack_params)

      unless turbo_frame_request?
        setup_metic_cards
        setup_chart_formatters
        @chart_data = Queries::Charts::AverageQueryTimes.new(
          ransack_query: @ransack_query,
          group_by: group_by,
          query: @query
        ).to_rails_chart
      end

      table_results = @ransack_query.result.select("id", "occurred_at", "duration")
      set_pagination_limit(params[:limit]) if params[:limit].present?
      @pagy, @table_data = pagy(table_results, limit: session_pagination_limit)
    end

    private

    def setup_time_and_response_ranges
      @start_time, @end_time, @selected_time_range, @time_diff_hours = setup_time_range
      @start_duration, @selected_response_range = setup_duration_range
    end

    def set_query
      @query = Query.find(params[:id])
    end

    def setup_metic_cards
      @average_query_times_card = Queries::Cards::AverageQueryTimes.new(query: @query).to_metric_card
      @percentile_response_times_card = Queries::Cards::PercentileQueryTimes.new(query: @query).to_metric_card
      @execution_rate_card = Queries::Cards::ExecutionRate.new(query: @query).to_metric_card
    end

    def setup_chart_formatters
      @xaxis_formatter = ChartFormatters.occurred_at_as_time_or_date(@time_diff_hours)
      @tooltip_formatter = ChartFormatters.tooltip_as_time_or_date_with_marker(@time_diff_hours)
    end

    def group_by
      @time_diff_hours <= 25 ? :group_by_hour : :group_by_day
    end
  end
end
