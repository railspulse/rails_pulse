module RailsPulse
  module Queries
    module Cards
      class PercentileQueryTimes
        def initialize(query: nil, disabled_tags: [], show_non_tagged: true)
          @query = query
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_metric_card
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          # Single query to get all P95 metrics with conditional aggregation
          base_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Query",
              period_type: "day",
              period_start: 2.weeks.ago.beginning_of_day..Time.current
            )
          base_query = base_query.where(summarizable_id: @query.id) if @query

          metrics = base_query.select(
            "AVG(p95_duration) AS overall_p95",
            "AVG(CASE WHEN period_start >= '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN p95_duration ELSE NULL END) AS current_p95",
            "AVG(CASE WHEN period_start >= '#{previous_7_days.strftime('%Y-%m-%d %H:%M:%S')}' AND period_start < '#{last_7_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN p95_duration ELSE NULL END) AS previous_p95"
          ).take

          # Calculate metrics from single query result
          p95_query_time = (metrics.overall_p95 || 0).round(0)
          current_period_p95 = metrics.current_p95 || 0
          previous_period_p95 = metrics.previous_p95 || 0

          percentage = previous_period_p95.zero? ? 0 : ((previous_period_p95 - current_period_p95) / previous_period_p95 * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_p95 < previous_period_p95 ? "trending-down" : "trending-up"
          trend_amount = previous_period_p95.zero? ? "0%" : "#{percentage}%"

          # Sparkline data by day with zero-filled days over the last 14 days
          grouped_daily = base_query
            .group_by_day(:period_start, time_zone: "UTC")
            .average(:p95_duration)

          start_day = 2.weeks.ago.beginning_of_day.to_date
          end_day = Time.current.to_date

          sparkline_data = {}
          (start_day..end_day).each do |day|
            avg = grouped_daily[day]&.round(0) || 0
            label = day.strftime("%b %-d")
            sparkline_data[label] = { value: avg }
          end

          {
            id: "percentile_query_times",
            context: "queries",
            title: "95th Percentile Query Time",
            summary: "#{p95_query_time} ms",
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
