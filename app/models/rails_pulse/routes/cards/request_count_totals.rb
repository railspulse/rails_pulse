module RailsPulse
  module Routes
    module Cards
      class RequestCountTotals
        def initialize(route: nil, disabled_tags: [], show_non_tagged: true)
          @route = route
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_metric_card
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          # Single query to get all count metrics with conditional aggregation
          base_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
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

          # Sparkline data by day with zero-filled days over the last 14 days
          grouped_daily = base_query
            .group_by_day(:period_start, time_zone: "UTC")
            .sum(:count)

          start_day = 2.weeks.ago.beginning_of_day.to_date
          end_day = Time.current.to_date

          sparkline_data = {}
          (start_day..end_day).each do |day|
            total = grouped_daily[day] || 0
            label = day.strftime("%b %-d")
            sparkline_data[label] = { value: total }
          end

          # Calculate appropriate rate display based on frequency
          total_minutes = 2.weeks / 1.minute.to_f
          requests_per_minute = total_request_count.to_f / total_minutes

          # Choose appropriate time unit for display
          if requests_per_minute >= 1
            summary = "#{requests_per_minute.round(2)} / min"
          elsif requests_per_minute * 60 >= 1
            requests_per_hour = requests_per_minute * 60
            summary = "#{requests_per_hour.round(2)} / hour"
          else
            requests_per_day = requests_per_minute * 60 * 24
            summary = "#{requests_per_day.round(2)} / day"
          end

          {
            id: "request_count_totals",
            context: "routes",
            title: "Request Count Total",
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
