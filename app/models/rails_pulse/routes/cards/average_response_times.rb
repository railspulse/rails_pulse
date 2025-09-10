module RailsPulse
  module Routes
    module Cards
      class AverageResponseTimes
        def initialize(route:)
          @route = route
        end

        def to_metric_card
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          # Single query to get all aggregated metrics with conditional sums
          base_query = RailsPulse::Summary.where(
            summarizable_type: "RailsPulse::Route",
            period_type: "day",
            period_start: 2.weeks.ago.beginning_of_day..Time.current
          )
          base_query = base_query.where(summarizable_id: @route.id) if @route

          metrics = base_query.select(
            "SUM(avg_duration * count) AS total_weighted_duration",
            "SUM(count) AS total_requests",
            "SUM(CASE WHEN period_start >= '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN avg_duration * count ELSE 0 END) AS current_weighted_duration",
            "SUM(CASE WHEN period_start >= '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN count ELSE 0 END) AS current_requests",
            "SUM(CASE WHEN period_start >= '#{previous_7_days.strftime('%Y-%m-%d %H:%M:%S')}' AND period_start < '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN avg_duration * count ELSE 0 END) AS previous_weighted_duration",
            "SUM(CASE WHEN period_start >= '#{previous_7_days.strftime('%Y-%m-%d %H:%M:%S')}' AND period_start < '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN count ELSE 0 END) AS previous_requests"
          ).take

          # Calculate metrics from single query result
          average_response_time = metrics.total_requests.to_i > 0 ? (metrics.total_weighted_duration / metrics.total_requests).round(0) : 0
          current_period_avg = metrics.current_requests.to_i > 0 ? (metrics.current_weighted_duration / metrics.current_requests) : 0
          previous_period_avg = metrics.previous_requests.to_i > 0 ? (metrics.previous_weighted_duration / metrics.previous_requests) : 0

          percentage = previous_period_avg.zero? ? 0 : ((previous_period_avg - current_period_avg) / previous_period_avg * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_avg < previous_period_avg ? "trending-down" : "trending-up"
          trend_amount = previous_period_avg.zero? ? "0%" : "#{percentage}%"

          # Sparkline data by day with zero-filled days over the last 14 days
          grouped_weighted = base_query
            .group_by_day(:period_start, time_zone: "UTC")
            .sum(Arel.sql("avg_duration * count"))

          grouped_counts = base_query
            .group_by_day(:period_start, time_zone: "UTC")
            .sum(:count)

          start_day = 2.weeks.ago.beginning_of_day.to_date
          end_day = Time.current.to_date

          sparkline_data = {}
          (start_day..end_day).each do |day|
            weighted_sum = grouped_weighted[day] || 0
            count_sum = grouped_counts[day] || 0
            avg = count_sum > 0 ? (weighted_sum.to_f / count_sum).round(0) : 0
            label = day.strftime("%b %-d")
            sparkline_data[label] = { value: avg }
          end

          {
            id: "average_response_times",
            context: "routes",
            title: "Average Response Time",
            summary: "#{average_response_time} ms",
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
