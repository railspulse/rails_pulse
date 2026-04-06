module RailsPulse
  module Routes
    module Cards
      class PercentileResponseTimes
        def initialize(route: nil, disabled_tags: [], show_non_tagged: true, period: 7)
          @route = route
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
          @period = period
        end

        def to_metric_card
          last_n_days = @period.days.ago.beginning_of_day
          previous_n_days = (@period * 2).days.ago.beginning_of_day

          # Single query to get all P95 metrics with conditional aggregation
          base_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: "day",
              period_start: (@period * 2).days.ago.beginning_of_day..Time.current
            )
          base_query = base_query.where(summarizable_id: @route.id) if @route

          last7 = last_n_days.strftime("%Y-%m-%d %H:%M:%S")
          prev7 = previous_n_days.strftime("%Y-%m-%d %H:%M:%S")

          metrics = base_query.select(
            "SUM(p95_duration * count) / NULLIF(SUM(count), 0) AS overall_p95",
            "SUM(CASE WHEN period_start >= '#{last7}' THEN p95_duration * count ELSE 0 END) / NULLIF(SUM(CASE WHEN period_start >= '#{last7}' THEN count ELSE 0 END), 0) AS current_p95",
            "SUM(CASE WHEN period_start >= '#{prev7}' AND period_start < '#{last7}' THEN p95_duration * count ELSE 0 END) / NULLIF(SUM(CASE WHEN period_start >= '#{prev7}' AND period_start < '#{last7}' THEN count ELSE 0 END), 0) AS previous_p95",
            "SUM(count) AS total_count"
          ).take

          # Calculate metrics from single query result
          p95_response_time = (metrics&.overall_p95 || 0).round(0)
          current_period_p95 = metrics&.current_p95 || 0
          previous_period_p95 = metrics&.previous_p95 || 0

          has_data = metrics.total_count.to_i > 0

          if has_data
            percentage = previous_period_p95.zero? ? 0 : ((previous_period_p95 - current_period_p95) / previous_period_p95 * 100).abs.round(1)
            trend_icon = percentage < 0.1 ? "move-right" : current_period_p95 < previous_period_p95 ? "trending-down" : "trending-up"
            trend_amount = previous_period_p95.zero? ? "0%" : "#{percentage}%"
          else
            trend_icon = "move-right"
            trend_amount = "—"
          end

          # Sparkline data by day with zero-filled days over the selected period
          weighted_sums = base_query.group_by_date(:period_start).sum("p95_duration * count")
          daily_counts = base_query.group_by_date(:period_start).sum(:count)

          start_day = @period.days.ago.beginning_of_day.to_date
          end_day = Time.current.to_date

          sparkline_data = {}
          (start_day..end_day).each do |day|
            total_count = daily_counts[day].to_i
            avg = total_count > 0 ? (weighted_sums[day].to_f / total_count).round(0) : 0
            label = day.strftime("%b %-d")
            sparkline_data[label] = { value: avg }
          end

          {
            id: "percentile_response_times",
            chart_color: RailsPulse::ChartColors::P95,
            context: "routes",
            title: "P95 Response Time",
            summary: has_data ? "#{p95_response_time} ms" : "—",
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week",
            help_heading: "P95 Response Time",
            help_text: "The 95th percentile response time — 95% of requests are faster than this. Weighted by request volume across all routes. A rising P95 indicates increasing slowness affecting your users."
          }
        end
      end
    end
  end
end
