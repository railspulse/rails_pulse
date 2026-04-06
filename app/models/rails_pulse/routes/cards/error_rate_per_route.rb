module RailsPulse
  module Routes
    module Cards
      class ErrorRatePerRoute
        def initialize(route: nil, disabled_tags: [], show_non_tagged: true, period: 7)
          @route = route
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
          @period = period
        end

        def to_metric_card
          last_n_days = @period.days.ago.beginning_of_day
          previous_n_days = (@period * 2).days.ago.beginning_of_day

          # Single query to get all error metrics with conditional aggregation
          base_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: "day",
              period_start: (@period * 2).days.ago.beginning_of_day..Time.current
            )
          base_query = base_query.where(summarizable_id: @route.id) if @route

          metrics = base_query.select(
            "SUM(error_count) AS total_errors",
            "SUM(count) AS total_requests",
            "SUM(CASE WHEN period_start >= '#{last_n_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN error_count ELSE 0 END) AS current_errors",
            "SUM(CASE WHEN period_start >= '#{previous_n_days.strftime('%Y-%m-%d %H:%M:%S')}' AND period_start < '#{last_n_days.strftime('%Y-%m-%d %H:%M:%S')}' THEN error_count ELSE 0 END) AS previous_errors"
          ).take

          # Calculate metrics from single query result
          total_errors = metrics.total_errors || 0
          total_requests = metrics.total_requests || 0
          current_period_errors = metrics.current_errors || 0
          previous_period_errors = metrics.previous_errors || 0

          has_data = total_requests > 0

          # Calculate overall error rate percentage
          overall_error_rate = has_data ? (total_errors.to_f / total_requests * 100).round(2) : 0

          # Calculate trend
          if has_data
            percentage = previous_period_errors.zero? ? 0 : ((previous_period_errors - current_period_errors) / previous_period_errors.to_f * 100).abs.round(1)
            trend_icon = percentage < 0.1 ? "move-right" : current_period_errors < previous_period_errors ? "trending-down" : "trending-up"
            trend_amount = previous_period_errors.zero? ? "0%" : "#{percentage}%"
          else
            trend_icon = "move-right"
            trend_amount = "—"
          end

          # Sparkline data by day with zero-filled days over the selected period
          grouped_daily = base_query
            .group_by_date(:period_start)
            .sum(:error_count)

          start_day = (@period * 2).days.ago.beginning_of_day.to_date
          end_day = Time.current.to_date

          sparkline_data = {}
          (start_day..end_day).each do |day|
            total = grouped_daily[day] || 0
            label = day.strftime("%b %-d")
            sparkline_data[label] = { value: total }
          end

          {
            id: "error_rate_per_route",
            chart_color: RailsPulse::ChartColors::DEFAULT,
            context: "routes",
            title: "Error Rate Per Route",
            summary: has_data ? "#{overall_error_rate}%" : "—",
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week",
            help_heading: "Server Error Rate (5xx)",
            help_text: "Percentage of requests returning 5xx status codes. Server errors indicate bugs, crashes, or infrastructure issues requiring immediate attention."
          }
        end
      end
    end
  end
end
