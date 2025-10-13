module RailsPulse
  module Queries
    module Cards
      class ExecutionRate
        def initialize(query: nil)
          @query = query
        end

        def to_metric_card
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          # Get the most common period type for this query, or fall back to "day"
          period_type = if @query
            RailsPulse::Summary.where(
              summarizable_type: "RailsPulse::Query",
              summarizable_id: @query.id
            ).group(:period_type).count.max_by(&:last)&.first || "day"
          else
            "day"
          end

          # Single query to get all count metrics with conditional aggregation
          base_query = RailsPulse::Summary.where(
            summarizable_type: "RailsPulse::Query",
            period_type: period_type,
            period_start: 2.weeks.ago.beginning_of_day..Time.current
          )
          base_query = base_query.where(summarizable_id: @query.id) if @query

          metrics = base_query.select(
            "SUM(count) AS total_count",
            "SUM(CASE WHEN period_start >= '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN count ELSE 0 END) AS current_count",
            "SUM(CASE WHEN period_start >= '#{previous_7_days.strftime('%Y-%m-%d %H:%M:%S')}' AND period_start < '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN count ELSE 0 END) AS previous_count"
          ).take

          # Calculate metrics from single query result
          total_execution_count = metrics.total_count || 0
          current_period_count = metrics.current_count || 0
          previous_period_count = metrics.previous_count || 0

          percentage = previous_period_count.zero? ? 0 : ((previous_period_count - current_period_count) / previous_period_count.to_f * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_count < previous_period_count ? "trending-down" : "trending-up"
          trend_amount = previous_period_count.zero? ? "0%" : "#{percentage}%"

          # Sparkline data with zero-filled periods over the last 14 days
          if period_type == "day"
            grouped_data = base_query
              .group_by_day(:period_start, time_zone: "UTC")
              .sum(:count)

            start_period = 2.weeks.ago.beginning_of_day.to_date
            end_period = Time.current.to_date

            sparkline_data = {}
            (start_period..end_period).each do |day|
              total = grouped_data[day] || 0
              label = day.strftime("%b %-d")
              sparkline_data[label] = { value: total }
            end
          else
            # For hourly data, group by day for sparkline display
            grouped_data = base_query
              .group("DATE(period_start)")
              .sum(:count)

            start_period = 2.weeks.ago.beginning_of_day.to_date
            end_period = Time.current.to_date

            sparkline_data = {}
            (start_period..end_period).each do |day|
              date_key = day.strftime("%Y-%m-%d")
              total = grouped_data[date_key] || 0
              label = day.strftime("%b %-d")
              sparkline_data[label] = { value: total }
            end
          end

          # Calculate appropriate rate display based on frequency
          total_minutes = 2.weeks / 1.minute.to_f
          executions_per_minute = total_execution_count.to_f / total_minutes

          # Choose appropriate time unit for display
          if executions_per_minute >= 1
            summary = "#{executions_per_minute.round(2)} / min"
          elsif executions_per_minute * 60 >= 1
            executions_per_hour = executions_per_minute * 60
            summary = "#{executions_per_hour.round(2)} / hour"
          else
            executions_per_day = executions_per_minute * 60 * 24
            summary = "#{executions_per_day.round(2)} / day"
          end

          {
            id: "execution_rate",
            context: "queries",
            title: "Execution Rate",
            summary: summary,
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week"
          }
        end
      end
    end
  end
end
