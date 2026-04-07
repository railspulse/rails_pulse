module RailsPulse
  class RoutesController < ApplicationController
    include ChartTableConcern
    include TagFilterConcern
    include MetricCardConcern

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

    # Metric card configuration - defines which cards to display
    def metric_card_definitions
      {
        percentile_response_times_metric_card: Routes::Cards::PercentileResponseTimes,
        request_count_totals_metric_card: Routes::Cards::RequestCountTotals,
        error_rates_metric_card: Routes::Cards::ErrorRates
      }
    end

    # The parameter name for passing the resource to metric cards
    def resource_key
      :route
    end

    # Chart configuration - defines which charts to render
    def chart_definitions
      {
        response_time_chart_data: Routes::Charts::ResponseTimePercentiles,
        request_rate_chart_data: Routes::Charts::RequestVolume,
        error_rate_chart_data: Routes::Charts::ErrorRate
      }
    end

    def chart_model
      Summary
    end

    def table_model
      show_action? ? Request : Summary
    end

    def chart_class
      Routes::Charts::ResponseTimePercentiles
    end

    # Pass the route to chart classes on show pages
    def chart_options
      show_action? ? { route: @route } : {}
    end

    # Filter to scope table results to a specific route on show pages
    def show_resource_filter
      { route_id_eq: @route.id }
    end

    # Returns the current route for metric cards and chart params
    def current_resource
      @route
    end

    def default_table_sort
      show_action? ? "occurred_at desc" : "p95_duration desc"
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

    def default_time_range_key
      :last_14_days
    end

    def duration_field
      :avg_duration
    end

    # Override table data setup to handle custom sorting logic for index page
    def setup_table_data(ransack_params)
      table_ransack_params = build_table_ransack_params(ransack_params)
      @ransack_query = table_model.ransack(table_ransack_params)

      # Only apply default sort if not using Routes::Tables::Index (which handles its own sorting)
      if show_action?
        @ransack_query.sorts = default_table_sort if @ransack_query.sorts.empty?
      end

      table_results = build_table_results
      handle_pagination

      @pagination, @table_data = paginate(table_results, limit: session_pagination_limit)
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
