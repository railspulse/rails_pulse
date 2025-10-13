module RailsPulse
  class RequestsController < ApplicationController
    include ChartTableConcern

    before_action :set_request, only: :show

    def index
      setup_metric_cards
      setup_chart_and_table_data
    end

    def show
      @operation_timeline = RailsPulse::Requests::Charts::OperationsChart.new(@request.operations)
    end

    private

    def setup_metric_cards
      return if  turbo_frame_request?

      @average_response_times_metric_card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: nil).to_metric_card
      @percentile_response_times_metric_card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil).to_metric_card
      @request_count_totals_metric_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil).to_metric_card
      @error_rate_per_route_metric_card = RailsPulse::Routes::Cards::ErrorRatePerRoute.new(route: nil).to_metric_card
    end


    def chart_model
      RailsPulse::Summary
    end

    def table_model
      RailsPulse::Request
    end

    def chart_class
      Requests::Charts::AverageResponseTimes
    end

    def chart_options
      {}
    end

    def build_chart_ransack_params(ransack_params)
      base_params = ransack_params.except(:s).merge(
        period_start_gteq: Time.at(@start_time),
        period_start_lt: Time.at(@end_time),
        summarizable_type_eq: "RailsPulse::Request",
        summarizable_id_eq: 0
      )

      # Only add duration filter if we have a meaningful threshold
      base_params[:avg_duration_gteq] = @start_duration if @start_duration && @start_duration > 0
      base_params
    end

    def build_table_ransack_params(ransack_params)
      params = ransack_params.merge(
        occurred_at_gteq: Time.at(@table_start_time),
        occurred_at_lt: Time.at(@table_end_time)
      )
      params[:duration_gteq] = @start_duration if @start_duration && @start_duration > 0
      params
    end

    def default_table_sort
      "occurred_at desc"
    end

    def build_table_results
      base_query = @ransack_query.result.includes(:route)

      # If sorting by route_path, we need to join the routes table
      if @ransack_query.sorts.any? { |sort| sort.name == "route_path" }
        base_query = base_query.joins(:route)
      end

      base_query
    end


    def setup_table_data(ransack_params)
      table_ransack_params = build_table_ransack_params(ransack_params)
      @ransack_query = table_model.ransack(table_ransack_params)

      # Only apply default sort if not using Requests::Tables::Index (which handles its own sorting)
      # For requests, we always use the Tables::Index on the index action
      unless action_name == "index"
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

    def set_request
      @request = Request.find(params[:id])
    end
  end
end
