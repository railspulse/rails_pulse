module RailsPulse
  class DashboardController < ApplicationController
    def index
      # Get tag filter values from session
      disabled_tags = session_disabled_tags
      show_non_tagged = session[:show_non_tagged] != false

      @average_query_times_metric_card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
      @percentile_response_times_metric_card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
      @request_count_totals_metric_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card
      @error_rate_per_route_metric_card = RailsPulse::Routes::Cards::ErrorRatePerRoute.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_metric_card

      # Generate chart data for inline rendering
      @average_response_time_chart_data = RailsPulse::Dashboard::Charts::AverageResponseTime.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_chart_data
      @p95_response_time_chart_data = RailsPulse::Dashboard::Charts::P95ResponseTime.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_chart_data

      # Generate table data for inline rendering
      @slow_routes_table_data = RailsPulse::Dashboard::Tables::SlowRoutes.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_table_data
      @slow_queries_table_data = RailsPulse::Dashboard::Tables::SlowQueries.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged).to_table_data
    end
  end
end
