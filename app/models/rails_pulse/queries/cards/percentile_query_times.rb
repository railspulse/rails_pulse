module RailsPulse
  module Queries
    module Cards
      class PercentileQueryTimes
        def initialize(query: nil, disabled_tags: [], show_non_tagged: true, period: 7, period_type: "day")
          @query = query
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
          @period = period
          @period_type = period_type
        end

        def to_metric_card
          # For hourly: period is in days (e.g., 1), but we work in hours
          # For daily: period is in days as before
          time_unit = @period_type == "hour" ? 1.hour : 1.day
          last_n_units = @period_type == "hour" ? (@period * 24).hours.ago : @period.days.ago.beginning_of_day
          previous_n_units = @period_type == "hour" ? (@period * 48).hours.ago : (@period * 2).days.ago.beginning_of_day

          # Single query to get all P95 metrics with conditional aggregation
          base_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Query",
              period_type: @period_type,
              period_start: previous_n_units..Time.current
            )
          base_query = base_query.where(summarizable_id: @query.id) if @query

          last7 = last_n_units.strftime("%Y-%m-%d %H:%M:%S")
          prev7 = previous_n_units.strftime("%Y-%m-%d %H:%M:%S")

          metrics = base_query.select(
            "SUM(p95_duration * count) / NULLIF(SUM(count), 0) AS overall_p95",
            "SUM(CASE WHEN period_start >= '#{last7}' THEN p95_duration * count ELSE 0 END) / NULLIF(SUM(CASE WHEN period_start >= '#{last7}' THEN count ELSE 0 END), 0) AS current_p95",
            "SUM(CASE WHEN period_start >= '#{prev7}' AND period_start < '#{last7}' THEN p95_duration * count ELSE 0 END) / NULLIF(SUM(CASE WHEN period_start >= '#{prev7}' AND period_start < '#{last7}' THEN count ELSE 0 END), 0) AS previous_p95"
          ).take

          # Calculate metrics from single query result
          p95_query_time = (metrics.overall_p95 || 0).round(0)
          current_period_p95 = metrics.current_p95 || 0
          previous_period_p95 = metrics.previous_p95 || 0

          percentage = previous_period_p95.zero? ? 0 : ((previous_period_p95 - current_period_p95) / previous_period_p95 * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_p95 < previous_period_p95 ? "trending-down" : "trending-up"
          trend_amount = previous_period_p95.zero? ? "0%" : "#{percentage}%"

          # Sparkline data - group by hour or day depending on period_type
          if @period_type == "hour"
            start_time = (@period * 24).hours.ago.beginning_of_hour
            end_time = Time.current.beginning_of_hour

            # Create a separate query for sparkline data using only the current period
            sparkline_query = RailsPulse::Summary
              .with_tag_filters(@disabled_tags, @show_non_tagged)
              .where(
                summarizable_type: "RailsPulse::Query",
                period_type: @period_type,
                period_start: start_time..end_time
              )
            sparkline_query = sparkline_query.where(summarizable_id: @query.id) if @query

            weighted_sums = sparkline_query.group_by_hour(:period_start).sum("p95_duration * count")
            period_counts = sparkline_query.group_by_hour(:period_start).sum(:count)

            sparkline_data = {}
            current_time = start_time
            while current_time <= end_time
              total_count = period_counts[current_time].to_i
              avg = total_count > 0 ? (weighted_sums[current_time].to_f / total_count).round(0) : 0
              # Use timestamp in milliseconds as key to preserve uniqueness across days
              sparkline_data[current_time.to_i * 1000] = { value: avg }
              current_time += 1.hour
            end
          else
            weighted_sums = base_query.group_by_date(:period_start).sum("p95_duration * count")
            period_counts = base_query.group_by_date(:period_start).sum(:count)

            start_day = @period.days.ago.beginning_of_day.to_date
            end_day = Time.current.to_date

            sparkline_data = {}
            (start_day..end_day).each do |day|
              total_count = period_counts[day].to_i
              avg = total_count > 0 ? (weighted_sums[day].to_f / total_count).round(0) : 0
              label = day.strftime("%b %-d")
              sparkline_data[label] = { value: avg }
            end
          end

          {
            id: "percentile_query_times",
            chart_color: RailsPulse::ChartColors::P95,
            context: "queries",
            title: "P95 Query Time",
            summary: "#{p95_query_time} ms",
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week",
            help_heading: "P95 Query Time",
            help_text: "The 95th percentile database query duration — 95% of queries complete faster than this. Weighted by execution frequency across all queries. Slow queries are often caused by missing indexes or N+1 patterns."
          }
        end
      end
    end
  end
end
