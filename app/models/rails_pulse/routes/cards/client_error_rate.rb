module RailsPulse
  module Routes
    module Cards
      class ClientErrorRate
        def initialize(route: nil, disabled_tags: [], show_non_tagged: true)
          @route = route
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_metric_card
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          base_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: "day",
              period_start: 2.weeks.ago.beginning_of_day..Time.current
            )
          base_query = base_query.where(summarizable_id: @route.id) if @route

          last7 = last_7_days.strftime("%Y-%m-%d %H:%M:%S")
          prev7 = previous_7_days.strftime("%Y-%m-%d %H:%M:%S")

          metrics = base_query.select(
            "SUM(status_4xx) AS total_4xx",
            "SUM(count) AS total_requests",
            "SUM(CASE WHEN period_start >= '#{last7}' THEN status_4xx ELSE 0 END) AS current_4xx",
            "SUM(CASE WHEN period_start >= '#{prev7}' AND period_start < '#{last7}' THEN status_4xx ELSE 0 END) AS previous_4xx"
          ).take

          total_4xx = metrics.total_4xx || 0
          total_requests = metrics.total_requests || 0
          current_period_4xx = metrics.current_4xx || 0
          previous_period_4xx = metrics.previous_4xx || 0

          has_data = total_requests > 0

          overall_rate = has_data ? (total_4xx.to_f / total_requests * 100).round(2) : 0

          if has_data
            percentage = previous_period_4xx.zero? ? 0 : ((previous_period_4xx - current_period_4xx) / previous_period_4xx.to_f * 100).abs.round(1)
            trend_icon = percentage < 0.1 ? "move-right" : current_period_4xx < previous_period_4xx ? "trending-down" : "trending-up"
            trend_amount = previous_period_4xx.zero? ? "0%" : "#{percentage}%"
          else
            trend_icon = "move-right"
            trend_amount = "—"
          end

          grouped_daily = base_query
            .group_by_date(:period_start)
            .sum(:status_4xx)

          start_day = 2.weeks.ago.beginning_of_day.to_date
          end_day = Time.current.to_date

          sparkline_data = {}
          (start_day..end_day).each do |day|
            total = grouped_daily[day] || 0
            label = day.strftime("%b %-d")
            sparkline_data[label] = { value: total }
          end

          {
            id: "client_error_rate",
            chart_color: RailsPulse::ChartColors::DEFAULT,
            context: "routes",
            title: "Client Error Rate",
            summary: has_data ? "#{overall_rate}%" : "—",
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week",
            help_heading: "Client Error Rate (4xx)",
            help_text: "Percentage of requests returning 4xx status codes (Not Found, Unauthorized, etc). High rates may indicate broken API consumers, deprecated endpoints still in use, or misconfigured clients."
          }
        end
      end
    end
  end
end
