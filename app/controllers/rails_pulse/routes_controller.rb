module RailsPulse
  class RoutesController < ApplicationController
    include ChartTableConcern
    include TagFilterConcern

    before_action :set_route, only: :show

    def index
      setup_metric_cards
      setup_chart_and_table_data
    end

    def show
      setup_metric_cards
      setup_chart_and_table_data
    end

    private

    def setup_metric_cards
      return if turbo_frame_request?

      # Get tag filter values from session
      disabled_tags = session_disabled_tags
      show_non_tagged = session[:show_non_tagged] != false

      @average_query_times_metric_card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
      @percentile_response_times_metric_card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
      @request_count_totals_metric_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
      @error_rate_per_route_metric_card = RailsPulse::Routes::Cards::ErrorRatePerRoute.new(route: @route, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
    end

    def chart_model
      Summary
    end

    def table_model
      show_action? ? Request : Summary
    end

    def chart_class
      Routes::Charts::AverageResponseTimes
    end

    def chart_options
      show_action? ? { route: @route } : {}
    end

    def build_chart_ransack_params(ransack_params)
      base_params = ransack_params.except(:s).merge(
        period_start_gteq: Time.at(@start_time),
        period_start_lt: Time.at(@end_time)
      )

      # Only add duration filter if we have a meaningful threshold
      base_params[:avg_duration_gteq] = @start_duration if @start_duration && @start_duration > 0

      if show_action?
        base_params.merge(summarizable_id_eq: @route.id)
      else
        base_params
      end
    end

    def build_table_ransack_params(ransack_params)
      if show_action?
        # For Request model on show page
        params = ransack_params.merge(
          occurred_at_gteq: Time.at(@table_start_time),
          occurred_at_lt: Time.at(@table_end_time),
          route_id_eq: @route.id
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
      show_action? ? "occurred_at desc" : "avg_duration desc"
    end

    def build_table_results
      if show_action?
        # Only show requests that belong to time periods where we have route summaries
        # This ensures the table data is consistent with the chart data
        # Note: We don't apply tag filters here because we want to show all requests
        # for this specific route, regardless of individual request tags
        base_query = @ransack_query.result
          .joins(<<~SQL)
            INNER JOIN rails_pulse_summaries ON
              rails_pulse_summaries.summarizable_id = rails_pulse_requests.route_id AND
              rails_pulse_summaries.summarizable_type = 'RailsPulse::Route' AND
              rails_pulse_summaries.period_type = '#{period_type}' AND
              rails_pulse_requests.occurred_at >= rails_pulse_summaries.period_start AND
              rails_pulse_requests.occurred_at < rails_pulse_summaries.period_end
          SQL

        # For PostgreSQL compatibility with DISTINCT + ORDER BY
        # we need to include computed columns in SELECT when ordering by them
        if ordering_by_computed_column?
          base_query.select("rails_pulse_requests.*, #{status_indicator_sql} as status_indicator_value").distinct
        else
          base_query.distinct
        end
      else
        Routes::Tables::Index.new(
          ransack_query: @ransack_query,
          period_type: period_type,
          start_time: @start_time,
          params: params,
          disabled_tags: session_disabled_tags,
          show_non_tagged: session[:show_non_tagged] != false
        ).to_table
      end
    end

    def duration_field
      :avg_duration
    end

    def show_action?
      action_name == "show"
    end

    def setup_table_data(ransack_params)
      table_ransack_params = build_table_ransack_params(ransack_params)
      @ransack_query = table_model.ransack(table_ransack_params)

      # Only apply default sort if not using Routes::Tables::Index (which handles its own sorting)
      if show_action?
        @ransack_query.sorts = default_table_sort if @ransack_query.sorts.empty?
      end

      table_results = build_table_results
      handle_pagination

      @pagy, @table_data = pagy(table_results, **pagy_options(session_pagination_limit))
    end

    def handle_pagination
      method = pagination_method
      send(method, params[:limit]) if params[:limit].present?
    end

    def pagination_method
      show_action? ? :set_pagination_limit : :store_pagination_limit
    end

    def set_route
      @route = Route.find(params[:id])
    end

    def ordering_by_computed_column?
      # Check if we're ordering by status_indicator (computed column)
      @ransack_query.sorts.any? { |sort| sort.name == "status_indicator" }
    end

    def status_indicator_sql
      # Same logic as in the Request model's ransacker
      config = RailsPulse.configuration rescue nil
      thresholds = config&.request_thresholds || { slow: 500, very_slow: 1000, critical: 2000 }
      slow = thresholds[:slow] || 500
      very_slow = thresholds[:very_slow] || 1000
      critical = thresholds[:critical] || 2000

      "CASE
        WHEN rails_pulse_requests.duration < #{slow} THEN 0
        WHEN rails_pulse_requests.duration < #{very_slow} THEN 1
        WHEN rails_pulse_requests.duration < #{critical} THEN 2
        ELSE 3
      END"
    end
  end
end
