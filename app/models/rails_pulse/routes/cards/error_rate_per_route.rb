module RailsPulse
  module Routes
    module Cards
      class ErrorRatePerRoute
        def initialize(route: nil)
          @route = route
        end

        def to_metric_card
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          # Single query to get all error metrics with conditional aggregation
          base_query = RailsPulse::Summary.where(
            summarizable_type: "RailsPulse::Route",
            period_type: "day",
            period_start: 2.weeks.ago.beginning_of_day..Time.current
          )
          base_query = base_query.where(summarizable_id: @route.id) if @route

          metrics = base_query.select(
            "SUM(error_count) AS total_errors",
            "SUM(count) AS total_requests",
            "SUM(CASE WHEN period_start >= '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN error_count ELSE 0 END) AS current_errors",
            "SUM(CASE WHEN period_start >= '#{previous_7_days.strftime('%Y-%m-%d %H:%M:%S')}' AND period_start < '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN error_count ELSE 0 END) AS previous_errors"
          ).take

          # Calculate metrics from single query result
          total_errors = metrics.total_errors || 0
          total_requests = metrics.total_requests || 0
          current_period_errors = metrics.current_errors || 0
          previous_period_errors = metrics.previous_errors || 0

          # Calculate overall error rate percentage
          overall_error_rate = total_requests > 0 ? (total_errors.to_f / total_requests * 100).round(2) : 0

          # Calculate trend
          percentage = previous_period_errors.zero? ? 0 : ((previous_period_errors - current_period_errors) / previous_period_errors.to_f * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_errors < previous_period_errors ? "trending-down" : "trending-up"
          trend_amount = previous_period_errors.zero? ? "0%" : "#{percentage}%"

          # Separate query for sparkline data - group by week using Rails
          sparkline_data = base_query
            .group_by_week(:period_start, time_zone: "UTC")
            .sum(:error_count)
            .each_with_object({}) do |(week_start, total_errors), hash|
              formatted_date = week_start.strftime("%b %-d")
              value = total_errors || 0
              hash[formatted_date] = { value: value }
            end

          {
            id: "error_rate_per_route",
            context: "routes",
            title: "Error Rate Per Route",
            summary: "#{overall_error_rate}%",
            line_chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week"
          }
        end
      end
    end
  end
end
