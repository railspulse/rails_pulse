module RailsPulse
  module Routes
    module Cards
      class AverageResponseTimes
        def initialize(route:)
          @route = route
        end

        def to_metric_card
          # Use daily stats for performance, fall back to raw data if needed
          average_response_time, current_period_avg, previous_period_avg, sparkline_data =
            if daily_stats_available?
              calculate_from_daily_stats
            else
              calculate_from_raw_data
            end

          # Calculate trend
          percentage = previous_period_avg.zero? ? 0 : ((previous_period_avg - current_period_avg) / previous_period_avg * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_avg < previous_period_avg ? "trending-down" : "trending-up"
          trend_amount = previous_period_avg.zero? ? "0%" : "#{percentage}%"

          {
            title: "Average Response Time",
            summary: "#{average_response_time} ms",
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
          current_hour_data = get_current_hour_raw_data

          # Calculate overall average (weighted by request count)
          total_requests = daily_stats.sum(:total_requests) + current_hour_data[:requests]
          if total_requests == 0
            return [ 0, 0, 0, {} ]
          end

          weighted_duration = daily_stats.sum("total_requests * avg_duration") +
                             (current_hour_data[:requests] * current_hour_data[:avg_duration])
          average_response_time = (weighted_duration / total_requests).round(0)

          # Calculate trend (last 7 days vs previous 7 days)
          last_7_days = daily_stats.where(date: 7.days.ago.to_date..Date.current)
          previous_7_days = daily_stats.where(date: 14.days.ago.to_date...7.days.ago.to_date)

          current_requests = last_7_days.sum(:total_requests) + current_hour_data[:requests]
          previous_requests = previous_7_days.sum(:total_requests)

          current_period_avg = if current_requests > 0
            (last_7_days.sum("total_requests * avg_duration") +
             (current_hour_data[:requests] * current_hour_data[:avg_duration])) / current_requests
          else
            0
          end

          previous_period_avg = if previous_requests > 0
            previous_7_days.sum("total_requests * avg_duration") / previous_requests
          else
            0
          end

          # Create sparkline data by week
          sparkline_data = build_sparkline_from_daily_stats(daily_stats, current_hour_data)

          [ average_response_time, current_period_avg, previous_period_avg, sparkline_data ]
        end

        def calculate_from_raw_data
          # Fallback to original raw data approach
          requests = if @route
            RailsPulse::Request.where(route: @route)
          else
            RailsPulse::Request.all
          end

          requests = requests.where("occurred_at >= ?", 2.weeks.ago.beginning_of_day)

          average_response_time = requests.average(:duration)&.round(0) || 0

          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day
          current_period_avg = requests.where("occurred_at >= ?", last_7_days).average(:duration) || 0
          previous_period_avg = requests.where("occurred_at >= ? AND occurred_at < ?", previous_7_days, last_7_days).average(:duration) || 0

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

          [ average_response_time, current_period_avg, previous_period_avg, sparkline_data ]
        end

        def get_current_hour_raw_data
          current_hour_start = Time.current.beginning_of_hour.utc
          current_hour_end = current_hour_start + 1.hour

          requests = if @route
            RailsPulse::Request.where(route: @route, occurred_at: current_hour_start...current_hour_end)
          else
            RailsPulse::Request.where(occurred_at: current_hour_start...current_hour_end)
          end

          request_count = requests.count
          avg_duration = request_count > 0 ? requests.average(:duration) || 0 : 0

          { requests: request_count, avg_duration: avg_duration }
        end

        def build_sparkline_from_daily_stats(daily_stats, current_hour_data)
          # Group by week for sparkline
          weekly_data = {}

          daily_stats.group_by { |stat| stat.date.beginning_of_week }.each do |week_start, stats|
            total_requests = stats.sum(&:total_requests)
            if total_requests > 0
              weighted_avg = stats.sum { |s| s.total_requests * s.avg_duration } / total_requests
              formatted_date = week_start.strftime("%b %-d")
              weekly_data[formatted_date] = { value: weighted_avg.round(0) }
            end
          end

          # Add current week data if we're in the current week
          current_week_start = Date.current.beginning_of_week
          if daily_stats.any? { |s| s.date >= current_week_start } || current_hour_data[:requests] > 0
            current_week_stats = daily_stats.select { |s| s.date >= current_week_start }
            current_week_requests = current_week_stats.sum(&:total_requests) + current_hour_data[:requests]

            if current_week_requests > 0
              weighted_avg = (current_week_stats.sum { |s| s.total_requests * s.avg_duration } +
                             (current_hour_data[:requests] * current_hour_data[:avg_duration])) / current_week_requests
              formatted_date = current_week_start.strftime("%b %-d")
              weekly_data[formatted_date] = { value: weighted_avg.round(0) }
            end
          end

          weekly_data
        end
      end
    end
  end
end
