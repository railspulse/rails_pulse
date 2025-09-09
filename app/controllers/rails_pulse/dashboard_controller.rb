module RailsPulse
  class DashboardController < ApplicationController
    def index
      @average_query_times_metric_card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: nil).to_metric_card
      @percentile_response_times_metric_card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil).to_metric_card
      @request_count_totals_metric_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil).to_metric_card
      @error_rate_per_route_metric_card = RailsPulse::Routes::Cards::ErrorRatePerRoute.new(route: nil).to_metric_card

      # Generate chart data for inline rendering
      @average_response_time_chart_data = RailsPulse::Dashboard::Charts::AverageResponseTime.new.to_chart_data
      @p95_response_time_chart_data = RailsPulse::Dashboard::Charts::P95ResponseTime.new.to_chart_data

      # Generate table data for inline rendering
      @slow_routes_table_data = RailsPulse::Dashboard::Tables::SlowRoutes.new.to_table_data
      @slow_queries_table_data = RailsPulse::Dashboard::Tables::SlowQueries.new.to_table_data
    end
  end
end
