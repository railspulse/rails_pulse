module RailsPulse
  module Routes
    module Cards
      class RequestCountTotals
        def initialize(route: nil)
          @route = route
        end

        def to_metric_card
          # Use daily stats for performance, fall back to raw data if needed
          average_requests_per_minute, current_period_count, previous_period_count, sparkline_data =
            if daily_stats_available?
              calculate_from_daily_stats
            else
              calculate_from_raw_data
            end

          # Calculate trend
          percentage = previous_period_count.zero? ? 0 : ((previous_period_count - current_period_count) / previous_period_count.to_f * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_count < previous_period_count ? "trending-down" : "trending-up"
          trend_amount = previous_period_count.zero? ? "0%" : "#{percentage}%"

          {
            title: "Request Count Total",
            summary: "#{average_requests_per_minute.round(2)} / min",
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
          current_hour_count = get_current_hour_count

          # Calculate total request count and requests per minute
          total_request_count = daily_stats.sum(:total_requests) + current_hour_count

          # Calculate average requests per minute over 2 weeks (2 weeks = 20,160 minutes)
          total_minutes = 14 * 24 * 60 # 2 weeks in minutes
          average_requests_per_minute = total_request_count.to_f / total_minutes

          # Calculate trend (last 7 days vs previous 7 days)
          last_7_days = daily_stats.where(date: 7.days.ago.to_date..Date.current)
          previous_7_days = daily_stats.where(date: 14.days.ago.to_date...7.days.ago.to_date)

          current_period_count = last_7_days.sum(:total_requests) + current_hour_count
          previous_period_count = previous_7_days.sum(:total_requests)

          # Create sparkline data by week
          sparkline_data = build_sparkline_from_daily_stats(daily_stats, current_hour_count)

          [ average_requests_per_minute, current_period_count, previous_period_count, sparkline_data ]
        end

        def calculate_from_raw_data
          # Fallback to original raw data approach
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

          [ average_requests_per_minute, current_period_count, previous_period_count, sparkline_data ]
        end

        def get_current_hour_count
          current_hour_start = Time.current.beginning_of_hour.utc
          current_hour_end = current_hour_start + 1.hour

          requests = if @route
            RailsPulse::Request.where(route: @route, occurred_at: current_hour_start...current_hour_end)
          else
            RailsPulse::Request.where(occurred_at: current_hour_start...current_hour_end)
          end

          requests.count
        end

        def build_sparkline_from_daily_stats(daily_stats, current_hour_count)
          # Group by week for sparkline
          weekly_data = {}

          daily_stats.group_by { |stat| stat.date.beginning_of_week }.each do |week_start, stats|
            total_requests = stats.sum(&:total_requests)
            formatted_date = week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: total_requests }
          end

          # Add current week data if we're in the current week
          current_week_start = Date.current.beginning_of_week
          if daily_stats.any? { |s| s.date >= current_week_start } || current_hour_count > 0
            current_week_stats = daily_stats.select { |s| s.date >= current_week_start }
            current_week_requests = current_week_stats.sum(&:total_requests) + current_hour_count
            formatted_date = current_week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: current_week_requests }
          end

          weekly_data
        end
      end
    end
  end
end
