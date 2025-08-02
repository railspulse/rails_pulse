module RailsPulse
  module Routes
    module Cards
      class ErrorRatePerRoute
        def initialize(route: nil)
          @route = route
        end

        def to_metric_card
          # Calculate error rate for each route or a specific route
          routes = if @route
            RailsPulse::Route.where(id: @route)
          else
            RailsPulse::Route.all
          end

          routes = routes.where("occurred_at >= ?", 2.weeks.ago.beginning_of_day)

          error_rates = routes.joins(:requests)
            .select("rails_pulse_routes.id, rails_pulse_routes.path, COUNT(rails_pulse_requests.id) as total_requests, SUM(CASE WHEN rails_pulse_requests.is_error = true THEN 1 ELSE 0 END) as error_count")
            .group("rails_pulse_routes.id, rails_pulse_routes.path")
            .map do |route|
              error_rate = route.error_count.to_f / route.total_requests * 100
              {
                path: route.path,
                error_rate: error_rate.round(2)
              }
            end

          # Calculate overall error rate summary as errors per day
          requests = @route ? RailsPulse::Request.where(route: @route) : RailsPulse::Request.all
          total_errors = requests.where(is_error: true).count
          min_time = requests.minimum(:occurred_at)
          max_time = requests.maximum(:occurred_at)
          total_days = min_time && max_time && min_time != max_time ? (max_time - min_time) / 1.day : 1
          errors_per_day = total_errors / total_days
          error_rate_summary = "#{errors_per_day.round(2)} / day"

          # Generate sparkline data
          sparkline_data = requests
            .where(is_error: true)
            .group_by_week(:occurred_at, time_zone: "UTC")
            .count
            .each_with_object({}) do |(date, count), hash|
              formatted_date = date.strftime("%b %-d")
              hash[formatted_date] = {
                value: count
              }
            end

          # Determine trend direction and amount
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day
          current_period_errors = requests.where("occurred_at >= ? AND is_error = ?", last_7_days, true).count
          previous_period_errors = requests.where("occurred_at >= ? AND occurred_at < ? AND is_error = ?", previous_7_days, last_7_days, true).count

          trend_amount = previous_period_errors.zero? ? "0%" : "#{((current_period_errors - previous_period_errors) / previous_period_errors.to_f * 100).round(1)}%"
          trend_icon = trend_amount.to_f < 0.1 ? "move-right" : current_period_errors < previous_period_errors ? "trending-down" : "trending-up"

          {
            title: "Error Rate Per Route",
            data: error_rates,
            summary: error_rate_summary,
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
