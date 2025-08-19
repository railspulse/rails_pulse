module RailsPulse
  module Requests
    module Cards
      class AverageResponseTimes
        def initialize(request: nil)
          @request = request
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
            summary: "#{average_response_time.round(0)} ms",
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

          # Add current hour raw data for real-time accuracy
          current_hour_avg = get_current_hour_avg

          # Calculate overall average (weighted by request count)
          total_requests = daily_stats.sum(:total_requests)
          weighted_avg = daily_stats.sum { |stat| stat.total_requests * stat.avg_duration }
          overall_avg = total_requests > 0 ? weighted_avg / total_requests : 0

          # Include current hour in overall average
          current_hour_count, current_hour_total = get_current_hour_data
          if current_hour_count > 0
            total_with_current = total_requests + current_hour_count
            weighted_with_current = weighted_avg + (current_hour_count * current_hour_avg)
            overall_avg = weighted_with_current / total_with_current
          end

          # Calculate trend (last 7 days vs previous 7 days)
          last_7_days = daily_stats.where(date: 7.days.ago.to_date..Date.current)
          previous_7_days = daily_stats.where(date: 14.days.ago.to_date...7.days.ago.to_date)

          current_period_avg = calculate_weighted_average(last_7_days, current_hour_avg, current_hour_count)
          previous_period_avg = calculate_weighted_average(previous_7_days)

          # Create sparkline data by week
          sparkline_data = build_sparkline_from_daily_stats(daily_stats, current_hour_avg, current_hour_count)

          [overall_avg, current_period_avg, previous_period_avg, sparkline_data]
        end

        def calculate_from_raw_data
          # Fallback to original raw data approach
          requests = RailsPulse::Request.where("occurred_at >= ?", 2.weeks.ago.beginning_of_day)

          # Calculate overall average response time
          average_response_time = requests.average(:duration) || 0

          # Calculate trend by comparing last 7 days vs previous 7 days
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

          [average_response_time, current_period_avg, previous_period_avg, sparkline_data]
        end

        def get_current_hour_avg
          current_hour_start = Time.current.beginning_of_hour.utc
          current_hour_end = current_hour_start + 1.hour

          requests = RailsPulse::Request.where(occurred_at: current_hour_start...current_hour_end)
          requests.average(:duration) || 0
        end

        def get_current_hour_data
          current_hour_start = Time.current.beginning_of_hour.utc
          current_hour_end = current_hour_start + 1.hour

          requests = RailsPulse::Request.where(occurred_at: current_hour_start...current_hour_end)
          [requests.count, requests.sum(:duration)]
        end

        def calculate_weighted_average(stats, current_hour_avg = 0, current_hour_count = 0)
          # Handle both ActiveRecord collections and arrays
          total_requests = if stats.is_a?(Array)
            stats.sum(&:total_requests)
          else
            stats.sum(:total_requests)
          end
          total_requests += current_hour_count
          return 0 if total_requests == 0

          weighted_sum = stats.sum { |stat| stat.total_requests * stat.avg_duration }
          weighted_sum += (current_hour_count * current_hour_avg)
          weighted_sum / total_requests
        end

        def build_sparkline_from_daily_stats(daily_stats, current_hour_avg, current_hour_count)
          # Group by week for sparkline
          weekly_data = {}

          daily_stats.group_by { |stat| stat.date.beginning_of_week }.each do |week_start, stats|
            avg_duration = calculate_weighted_average(stats)
            formatted_date = week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: avg_duration.round(0) }
          end

          # Add current week data if we're in the current week
          current_week_start = Date.current.beginning_of_week
          if daily_stats.any? { |s| s.date >= current_week_start } || current_hour_count > 0
            current_week_stats = daily_stats.select { |s| s.date >= current_week_start }
            current_week_avg = calculate_weighted_average(current_week_stats, current_hour_avg, current_hour_count)
            formatted_date = current_week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: current_week_avg.round(0) }
          end

          weekly_data
        end
      end
    end
  end
end