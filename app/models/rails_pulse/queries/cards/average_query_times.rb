module RailsPulse
  module Queries
    module Cards
      class AverageQueryTimes
        def initialize(query: nil)
          @query = query
        end

        def to_metric_card
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          # Single query to get all aggregated metrics with conditional sums
          base_query = RailsPulse::Summary.where(
            summarizable_type: "RailsPulse::Query",
            period_type: "day",
            period_start: 2.weeks.ago.beginning_of_day..Time.current
          )
          base_query = base_query.where(summarizable_id: @query.id) if @query

          metrics = base_query.select(
            "SUM(avg_duration * count) AS total_weighted_duration",
            "SUM(count) AS total_requests",
            "SUM(CASE WHEN period_start >= '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN avg_duration * count ELSE 0 END) AS current_weighted_duration",
            "SUM(CASE WHEN period_start >= '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN count ELSE 0 END) AS current_requests",
            "SUM(CASE WHEN period_start >= '#{previous_7_days.strftime('%Y-%m-%d %H:%M:%S')}' AND period_start < '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN avg_duration * count ELSE 0 END) AS previous_weighted_duration",
            "SUM(CASE WHEN period_start >= '#{previous_7_days.strftime('%Y-%m-%d %H:%M:%S')}' AND period_start < '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN count ELSE 0 END) AS previous_requests"
          ).first

          # Calculate metrics from single query result
          average_query_time = metrics.total_requests.to_i > 0 ? (metrics.total_weighted_duration / metrics.total_requests).round(0) : 0
          current_period_avg = metrics.current_requests.to_i > 0 ? (metrics.current_weighted_duration / metrics.current_requests) : 0
          previous_period_avg = metrics.previous_requests.to_i > 0 ? (metrics.previous_weighted_duration / metrics.previous_requests) : 0

          percentage = previous_period_avg.zero? ? 0 : ((previous_period_avg - current_period_avg) / previous_period_avg * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_avg < previous_period_avg ? "trending-down" : "trending-up"
          trend_amount = previous_period_avg.zero? ? "0%" : "#{percentage}%"

          # Separate query for sparkline data - manually calculate weighted averages by week
          sparkline_data = {}
          base_query.each do |summary|
            week_start = summary.period_start.beginning_of_week
            formatted_date = week_start.strftime("%b %-d")

            if sparkline_data[formatted_date]
              sparkline_data[formatted_date][:total_weighted] += (summary.avg_duration || 0) * (summary.count || 0)
              sparkline_data[formatted_date][:total_count] += (summary.count || 0)
            else
              sparkline_data[formatted_date] = {
                total_weighted: (summary.avg_duration || 0) * (summary.count || 0),
                total_count: (summary.count || 0)
              }
            end
          end

          # Convert to final format
          sparkline_data = sparkline_data.transform_values do |data|
            weighted_avg = data[:total_count] > 0 ? (data[:total_weighted] / data[:total_count]).round(0) : 0
            { value: weighted_avg }
          end

          {
            id: "average_query_times",
            context: "queries",
            title: "Average Query Time",
            summary: "#{average_query_time} ms",
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
