module RailsPulse
  module Routes
    module Cards
      class AverageResponseTimes
        def initialize(route:)
          @route = route
        end

        def to_metric_card
          requests = if @route
            RailsPulse::Request.where(route: @route)
          else
            RailsPulse::Request.all
          end

          requests = requests.where("occurred_at >= ?", 2.weeks.ago.beginning_of_day)

          # Calculate overall average response time
          average_response_time = requests.average(:duration)&.round(0) || 0

          # Calculate trend by comparing last 7 days vs previous 7 days
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day
          current_period_avg = requests.where("occurred_at >= ?", last_7_days).average(:duration) || 0
          previous_period_avg = requests.where("occurred_at >= ? AND occurred_at < ?", previous_7_days, last_7_days).average(:duration) || 0

          percentage = previous_period_avg.zero? ?  0 : ((previous_period_avg - current_period_avg) / previous_period_avg * 100).abs.round(1)
          trend_icon = percentage < 0.1 ?  "move-right" : current_period_avg < previous_period_avg ? "trending-down" : "trending-up"
          trend_amount = previous_period_avg.zero? ? "0%" : "#{percentage}%"

          sparkline_data = requests
            .group_by_week(:occurred_at, time_zone: "UTC")
            .average(:duration)
            .each_with_object({}) do |(date, avg), hash|
              formatted_date = date.strftime("%b %-d")
              value = avg&.round(0) || 0
              hash[formatted_date] = {
                value: value
              }
            end

          {
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
