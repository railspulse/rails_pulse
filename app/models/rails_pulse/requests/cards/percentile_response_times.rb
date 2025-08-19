module RailsPulse
  module Requests
    module Cards
      class PercentileResponseTimes
        def initialize(request: nil)
          @request = request
        end

        def to_metric_card
          # Use daily stats for performance, fall back to raw data if needed
          percentile_95th, current_period_95th, previous_period_95th, sparkline_data =
            if daily_stats_available?
              calculate_from_daily_stats
            else
              calculate_from_raw_data
            end

          # Calculate trend
          percentage = previous_period_95th.zero? ? 0 : ((previous_period_95th - current_period_95th) / previous_period_95th * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_95th < previous_period_95th ? "trending-down" : "trending-up"
          trend_amount = previous_period_95th.zero? ? "0%" : "#{percentage}%"

          {
            title: "95th Percentile Response Time",
            summary: "#{percentile_95th.round(0)} ms",
            line_chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week"
          }
        end

        private

        def daily_stats_available?
          # Check if we have daily stats for requests entity
          stats_count = RailsPulse::DailyStat
            .for_entity("request", nil)
            .where(date: 7.days.ago.to_date..Date.current)
            .count
          stats_count >= 5 # Need reasonable coverage
        end

        def calculate_from_daily_stats
          # Get daily stats for the last 2 weeks
          daily_stats = RailsPulse::DailyStat
            .for_entity("request", nil)
            .for_date_range(14.days.ago.to_date, Date.current)
            .where("total_requests > 0") # Only finalized stats

          # Calculate overall 95th percentile from daily stats
          overall_95th = daily_stats.average(:p95_duration) || 0

          # Add current hour raw data for real-time accuracy
          current_hour_95th = get_current_hour_95th

          # Calculate trend (last 7 days vs previous 7 days)
          last_7_days = daily_stats.where(date: 7.days.ago.to_date..Date.current)
          previous_7_days = daily_stats.where(date: 14.days.ago.to_date...7.days.ago.to_date)

          current_period_95th = last_7_days.average(:p95_duration) || current_hour_95th
          previous_period_95th = previous_7_days.average(:p95_duration) || 0

          # Create sparkline data by week
          sparkline_data = build_sparkline_from_daily_stats(daily_stats, current_hour_95th)

          [overall_95th, current_period_95th, previous_period_95th, sparkline_data]
        end

        def calculate_from_raw_data
          # Fallback to original raw data approach
          requests = RailsPulse::Request.where("occurred_at >= ?", 2.weeks.ago.beginning_of_day)

          # Calculate overall 95th percentile response time
          count = requests.count
          percentile_95th = if count > 0
            requests.select("duration").order("duration").limit(1).offset((count * 0.95).floor).pluck(:duration).first || 0
          else
            0
          end

          # Calculate trend by comparing last 7 days vs previous 7 days for 95th percentile
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          current_period = requests.where("occurred_at >= ?", last_7_days)
          current_count = current_period.count
          current_period_95th = if current_count > 0
            current_period.select("duration").order("duration").limit(1).offset((current_count * 0.95).floor).pluck(:duration).first || 0
          else
            0
          end

          previous_period = requests.where("occurred_at >= ? AND occurred_at < ?", previous_7_days, last_7_days)
          previous_count = previous_period.count
          previous_period_95th = if previous_count > 0
            previous_period.select("duration").order("duration").limit(1).offset((previous_count * 0.95).floor).pluck(:duration).first || 0
          else
            0
          end

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

          [percentile_95th, current_period_95th, previous_period_95th, sparkline_data]
        end

        def get_current_hour_95th
          current_hour_start = Time.current.beginning_of_hour.utc
          current_hour_end = current_hour_start + 1.hour

          requests = RailsPulse::Request.where(occurred_at: current_hour_start...current_hour_end)
          count = requests.count
          return 0 if count == 0

          durations = requests.pluck(:duration).sort
          index = (count * 0.95).ceil - 1
          durations[index] || 0
        end

        def build_sparkline_from_daily_stats(daily_stats, current_hour_95th)
          # Group by week for sparkline
          weekly_data = {}

          daily_stats.group_by { |stat| stat.date.beginning_of_week }.each do |week_start, stats|
            avg_p95 = stats.sum(&:p95_duration) / stats.size
            formatted_date = week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: avg_p95.round(0) }
          end

          # Add current week data if we're in the current week
          current_week_start = Date.current.beginning_of_week
          if daily_stats.any? { |s| s.date >= current_week_start } || current_hour_95th > 0
            current_week_stats = daily_stats.select { |s| s.date >= current_week_start }
            current_week_p95 = if current_week_stats.any?
              (current_week_stats.sum(&:p95_duration) + current_hour_95th) / (current_week_stats.size + 1)
            else
              current_hour_95th
            end
            formatted_date = current_week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: current_week_p95.round(0) }
          end

          weekly_data
        end
      end
    end
  end
end