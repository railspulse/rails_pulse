module RailsPulse
  module Routes
    module Cards
      class RequestCountTotals
        def initialize(route: nil)
          @route = route
        end

        def to_metric_card
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          # Single query to get all count metrics with conditional aggregation
          base_query = RailsPulse::Summary.where(
            summarizable_type: "RailsPulse::Route",
            period_type: "day",
            period_start: 2.weeks.ago.beginning_of_day..Time.current
          )
          base_query = base_query.where(summarizable_id: @route.id) if @route

          metrics = base_query.select(
            "SUM(count) AS total_count",
            "SUM(CASE WHEN period_start >= '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN count ELSE 0 END) AS current_count",
            "SUM(CASE WHEN period_start >= '#{previous_7_days.strftime('%Y-%m-%d %H:%M:%S')}' AND period_start < '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN count ELSE 0 END) AS previous_count"
          ).take

          # Calculate metrics from single query result
          total_request_count = metrics.total_count || 0
          current_period_count = metrics.current_count || 0
          previous_period_count = metrics.previous_count || 0

          percentage = previous_period_count.zero? ? 0 : ((previous_period_count - current_period_count) / previous_period_count.to_f * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_count < previous_period_count ? "trending-down" : "trending-up"
          trend_amount = previous_period_count.zero? ? "0%" : "#{percentage}%"

          # Separate query for sparkline data - group by week using Rails
          sparkline_data = base_query
            .group_by_week(:period_start, time_zone: "UTC")
            .sum(:count)
            .each_with_object({}) do |(week_start, total_count), hash|
              formatted_date = week_start.strftime("%b %-d")
              value = total_count || 0
              hash[formatted_date] = { value: value }
            end

          # Calculate average requests per minute over 2-week period
          total_minutes = 2.weeks / 1.minute
          average_requests_per_minute = total_request_count / total_minutes

          {
            id: "request_count_totals",
            context: "routes",
            title: "Request Count Total",
            summary: "#{average_requests_per_minute.round(2)} / min",
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
