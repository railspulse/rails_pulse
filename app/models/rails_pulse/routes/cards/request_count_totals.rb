module RailsPulse
  module Routes
    module Cards
      class RequestCountTotals
        def initialize(route: nil)
          @route = route
        end

        def to_metric_card
          requests = if @route
            RailsPulse::Request.where(route: @route)
          else
            RailsPulse::Request.all
          end

          requests = requests.where("occurred_at >= ?", 2.weeks.ago.beginning_of_day)

          # Calculate total request count
          total_request_count = requests.count

          # Calculate trend by comparing last 7 days vs previous 7 days
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day
          current_period_count = requests.where("occurred_at >= ?", last_7_days).count
          previous_period_count = requests.where("occurred_at >= ? AND occurred_at < ?", previous_7_days, last_7_days).count

          percentage = previous_period_count.zero? ? 0 : ((previous_period_count - current_period_count) / previous_period_count.to_f * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_count < previous_period_count ? "trending-down" : "trending-up"
          trend_amount = previous_period_count.zero? ? "0%" : "#{percentage}%"

          sparkline_data = requests
            .group_by_week(:occurred_at, time_zone: "UTC")
            .count
            .each_with_object({}) do |(date, count), hash|
              formatted_date = date.strftime("%b %-d")
              hash[formatted_date] = {
                value: count
              }
            end

          # Calculate average requests per minute
          min_time = requests.minimum(:occurred_at)
          max_time = requests.maximum(:occurred_at)
          total_minutes = min_time && max_time && min_time != max_time ? (max_time - min_time) / 60.0 : 1
          average_requests_per_minute = total_request_count / total_minutes

          {
            title: "Request Count Total",
            summary: "#{average_requests_per_minute.round(2)} / min",
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
