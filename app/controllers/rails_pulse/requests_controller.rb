module RailsPulse
  class RequestsController < ApplicationController
    include ChartTableConcern
    include TagFilterConcern

    # Override TIME_RANGE_OPTIONS from TimeRangeConcern with requests-specific options
    remove_const(:TIME_RANGE_OPTIONS) if const_defined?(:TIME_RANGE_OPTIONS)
    TIME_RANGE_OPTIONS = [
      [ "Recent", "recent" ],
      [ "Custom Range", "custom" ]
    ].freeze

    before_action :set_request, only: :show

    def index
      setup_metric_cards
      setup_chart_and_table_data
    end

    def show
      @operation_timeline = RailsPulse::Charts::OperationsChart.new(@request.operations)
    end

    private

    def setup_metric_cards
      return if  turbo_frame_request?

      # Get tag filter values from session
      disabled_tags = session_disabled_tags
      show_non_tagged = session[:show_non_tagged] != false

      @average_response_times_metric_card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
      @percentile_response_times_metric_card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
      @request_count_totals_metric_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
      @error_rate_per_route_metric_card = RailsPulse::Routes::Cards::ErrorRatePerRoute.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
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
      params = ransack_params.dup

      # Handle time mode - check if recent mode is selected
      time_mode = params[:period_start_range] || "recent"

      if time_mode != "recent"
        # Custom mode - apply time filters
        params.merge!(
          occurred_at_gteq: Time.at(@table_start_time),
          occurred_at_lt: Time.at(@table_end_time)
        )
      end
      # else: Recent mode - no time filters, just rely on sort + pagination

      # Duration filter - convert symbol to numeric threshold or use @start_duration
      if params[:duration_gteq].present?
        # If it's a symbol like :slow, convert it to the numeric threshold
        if params[:duration_gteq].to_s.in?(%w[slow very_slow critical])
          params[:duration_gteq] = @start_duration
        end
        # else: it's already a number, keep it as is
      elsif @start_duration && @start_duration > 0
        # No duration_gteq param, use @start_duration from concern
        params[:duration_gteq] = @start_duration
      end

      params
    end

    def default_table_sort
      "occurred_at desc"
    end

    def build_table_results
      base_query = apply_tag_filters(@ransack_query.result.includes(:route))

      # If filtering or sorting by route_path, we need to join the routes table
      needs_join = @ransack_query.sorts.any? { |sort| sort.name == "route_path" } ||
                   params.dig(:q, :route_path_cont).present?

      if needs_join
        base_query = base_query.joins(:route)
      end

      base_query
    end


    def setup_table_data(ransack_params)
      table_ransack_params = build_table_ransack_params(ransack_params)
      @ransack_query = table_model.ransack(table_ransack_params)
      @ransack_query.sorts = default_table_sort if @ransack_query.sorts.empty?

      table_results = build_table_results
      handle_pagination

      @pagy, @table_data = pagy(table_results, **pagy_options(session_pagination_limit))
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
