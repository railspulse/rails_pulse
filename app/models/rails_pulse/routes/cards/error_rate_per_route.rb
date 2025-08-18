module RailsPulse
  module Routes
    module Cards
      class ErrorRatePerRoute
        def initialize(route: nil)
          @route = route
        end

        def to_metric_card
          # Use daily stats for performance, fall back to raw data if needed
          error_rates, error_rate_summary, current_period_errors, previous_period_errors, sparkline_data =
            if daily_stats_available?
              calculate_from_daily_stats
            else
              calculate_from_raw_data
            end

          # Calculate trend
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

        private

        def daily_stats_available?
          # Check if we have daily stats for at least the last 7 days
          stats_count = RailsPulse::DailyStat
            .for_entity("route", @route&.id)
            .where(date: 7.days.ago.to_date..Date.current)
            .count
          stats_count >= 5 # Need reasonable coverage
        end

        def calculate_from_daily_stats
          # Get daily stats for the last 2 weeks
          daily_stats = RailsPulse::DailyStat
            .for_entity("route", @route&.id)
            .for_date_range(14.days.ago.to_date, Date.current)
            .where("total_requests > 0") # Only finalized stats

          # Add current hour raw data for real-time accuracy
          current_hour_errors = get_current_hour_errors

          # Calculate error rates per route
          error_rates = if @route
            # Single route
            total_requests = daily_stats.sum(:total_requests) + current_hour_errors[:count]
            total_errors = daily_stats.sum(:error_count) + current_hour_errors[:errors]
            error_rate = total_requests > 0 ? (total_errors.to_f / total_requests * 100) : 0
            [ {
              path: @route.path,
              error_rate: error_rate.round(2)
            } ]
          else
            # All routes - group by route_id and calculate sums separately
            grouped_stats = daily_stats.group(:entity_id)
            request_sums = grouped_stats.sum(:total_requests)
            error_sums = grouped_stats.sum(:error_count)

            request_sums.map do |route_id, total_requests|
              route = RailsPulse::Route.find(route_id)
              total_errors = error_sums[route_id] || 0
              error_rate = total_requests > 0 ? (total_errors.to_f / total_requests * 100) : 0
              {
                path: route.path,
                error_rate: error_rate.round(2)
              }
            end
          end

          # Calculate overall error rate summary as errors per day
          total_errors = daily_stats.sum(:error_count) + current_hour_errors[:errors]
          errors_per_day = total_errors.to_f / 14 # 2 weeks in days
          error_rate_summary = "#{errors_per_day.round(2)} / day"

          # Calculate trend (last 7 days vs previous 7 days)
          last_7_days = daily_stats.where(date: 7.days.ago.to_date..Date.current)
          previous_7_days = daily_stats.where(date: 14.days.ago.to_date...7.days.ago.to_date)

          current_period_errors = last_7_days.sum(:error_count) + current_hour_errors[:errors]
          previous_period_errors = previous_7_days.sum(:error_count)

          # Create sparkline data by week
          sparkline_data = build_sparkline_from_daily_stats(daily_stats, current_hour_errors[:errors])

          [ error_rates, error_rate_summary, current_period_errors, previous_period_errors, sparkline_data ]
        end

        def calculate_from_raw_data
          # Fallback to original raw data approach
          routes = if @route
            RailsPulse::Route.where(id: @route)
          else
            RailsPulse::Route.all
          end

          error_rates = routes.joins(:requests)
            .where("rails_pulse_requests.occurred_at >= ?", 2.weeks.ago.beginning_of_day)
            .select("rails_pulse_routes.id, rails_pulse_routes.path, COUNT(rails_pulse_requests.id) as total_requests, SUM(CASE WHEN rails_pulse_requests.is_error = true THEN 1 ELSE 0 END) as error_count")
            .group("rails_pulse_routes.id, rails_pulse_routes.path")
            .map do |route|
              error_rate = route.total_requests > 0 ? (route.error_count.to_f / route.total_requests * 100) : 0
              {
                path: route.path,
                error_rate: error_rate.round(2)
              }
            end

          # Calculate overall error rate summary as errors per day
          requests = @route ? RailsPulse::Request.where(route: @route) : RailsPulse::Request.all
          total_errors = requests.where("occurred_at >= ? AND is_error = ?", 2.weeks.ago.beginning_of_day, true).count
          errors_per_day = total_errors.to_f / 14
          error_rate_summary = "#{errors_per_day.round(2)} / day"

          # Generate sparkline data
          sparkline_data = requests
            .where("occurred_at >= ? AND is_error = ?", 2.weeks.ago.beginning_of_day, true)
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

          [ error_rates, error_rate_summary, current_period_errors, previous_period_errors, sparkline_data ]
        end

        def get_current_hour_errors
          current_hour_start = Time.current.beginning_of_hour.utc
          current_hour_end = current_hour_start + 1.hour

          requests = if @route
            RailsPulse::Request.where(route: @route, occurred_at: current_hour_start...current_hour_end)
          else
            RailsPulse::Request.where(occurred_at: current_hour_start...current_hour_end)
          end

          total_count = requests.count
          error_count = requests.where(is_error: true).count

          { count: total_count, errors: error_count }
        end

        def build_sparkline_from_daily_stats(daily_stats, current_hour_errors)
          # Group by week for sparkline
          weekly_data = {}

          daily_stats.group_by { |stat| stat.date.beginning_of_week }.each do |week_start, stats|
            total_errors = stats.sum(&:error_count)
            formatted_date = week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: total_errors }
          end

          # Add current week data if we're in the current week
          current_week_start = Date.current.beginning_of_week
          if daily_stats.any? { |s| s.date >= current_week_start } || current_hour_errors > 0
            current_week_stats = daily_stats.select { |s| s.date >= current_week_start }
            current_week_errors = current_week_stats.sum(&:error_count) + current_hour_errors
            formatted_date = current_week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: current_week_errors }
          end

          weekly_data
        end
      end
    end
  end
end
