module RailsPulse
  module Requests
    module Cards
      class ErrorRatePerRoute
        def initialize(request: nil)
          @request = request
        end

        def to_metric_card
          # Use daily stats for performance, fall back to raw data if needed
          error_rate, current_period_rate, previous_period_rate, sparkline_data =
            if daily_stats_available?
              calculate_from_daily_stats
            else
              calculate_from_raw_data
            end

          # Calculate trend
          percentage = previous_period_rate.zero? ? 0 : ((previous_period_rate - current_period_rate) / previous_period_rate * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_rate < previous_period_rate ? "trending-down" : "trending-up"
          trend_amount = previous_period_rate.zero? ? "0%" : "#{percentage}%"

          {
            title: "Error Rate",
            summary: "#{error_rate.round(2)}%",
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
          current_hour_errors, current_hour_total = get_current_hour_error_data

          # Calculate overall error rate
          total_requests = daily_stats.sum(:total_requests) + current_hour_total
          total_errors = daily_stats.sum(:error_count) + current_hour_errors
          overall_error_rate = total_requests > 0 ? (total_errors.to_f / total_requests * 100) : 0

          # Calculate trend (last 7 days vs previous 7 days)
          last_7_days = daily_stats.where(date: 7.days.ago.to_date..Date.current)
          previous_7_days = daily_stats.where(date: 14.days.ago.to_date...7.days.ago.to_date)

          current_requests = last_7_days.sum(:total_requests) + current_hour_total
          current_errors = last_7_days.sum(:error_count) + current_hour_errors
          current_period_rate = current_requests > 0 ? (current_errors.to_f / current_requests * 100) : 0

          previous_requests = previous_7_days.sum(:total_requests)
          previous_errors = previous_7_days.sum(:error_count)
          previous_period_rate = previous_requests > 0 ? (previous_errors.to_f / previous_requests * 100) : 0

          # Create sparkline data by week
          sparkline_data = build_sparkline_from_daily_stats(daily_stats, current_hour_errors, current_hour_total)

          [overall_error_rate, current_period_rate, previous_period_rate, sparkline_data]
        end

        def calculate_from_raw_data
          # Fallback to original raw data approach
          requests = RailsPulse::Request.where("occurred_at >= ?", 2.weeks.ago.beginning_of_day)

          # Calculate overall error rate
          total_count = requests.count
          error_count = requests.where(is_error: true).count
          error_rate = total_count > 0 ? (error_count.to_f / total_count * 100) : 0

          # Calculate trend by comparing last 7 days vs previous 7 days
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          current_period = requests.where("occurred_at >= ?", last_7_days)
          current_total = current_period.count
          current_errors = current_period.where(is_error: true).count
          current_period_rate = current_total > 0 ? (current_errors.to_f / current_total * 100) : 0

          previous_period = requests.where("occurred_at >= ? AND occurred_at < ?", previous_7_days, last_7_days)
          previous_total = previous_period.count
          previous_errors = previous_period.where(is_error: true).count
          previous_period_rate = previous_total > 0 ? (previous_errors.to_f / previous_total * 100) : 0

          sparkline_data = {}
          weekly_data = requests.group_by_week(:occurred_at, time_zone: "UTC")

          weekly_data.group(:is_error).count.each do |(date, is_error), count|
            formatted_date = date.strftime("%b %-d")
            sparkline_data[formatted_date] ||= { total: 0, errors: 0 }
            
            if is_error
              sparkline_data[formatted_date][:errors] = count
            else
              sparkline_data[formatted_date][:total] += count
            end
          end

          # Convert to error rate percentages
          sparkline_data.transform_values! do |data|
            total_with_errors = data[:total] + data[:errors]
            rate = total_with_errors > 0 ? (data[:errors].to_f / total_with_errors * 100) : 0
            { value: rate.round(2) }
          end

          [error_rate, current_period_rate, previous_period_rate, sparkline_data]
        end

        def get_current_hour_error_data
          current_hour_start = Time.current.beginning_of_hour.utc
          current_hour_end = current_hour_start + 1.hour

          requests = RailsPulse::Request.where(occurred_at: current_hour_start...current_hour_end)
          [requests.where(is_error: true).count, requests.count]
        end

        def build_sparkline_from_daily_stats(daily_stats, current_hour_errors, current_hour_total)
          # Group by week for sparkline
          weekly_data = {}

          daily_stats.group_by { |stat| stat.date.beginning_of_week }.each do |week_start, stats|
            total_requests = stats.sum(&:total_requests)
            total_errors = stats.sum(&:error_count)
            error_rate = total_requests > 0 ? (total_errors.to_f / total_requests * 100) : 0
            formatted_date = week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: error_rate.round(2) }
          end

          # Add current week data if we're in the current week
          current_week_start = Date.current.beginning_of_week
          if daily_stats.any? { |s| s.date >= current_week_start } || current_hour_total > 0
            current_week_stats = daily_stats.select { |s| s.date >= current_week_start }
            current_week_requests = current_week_stats.sum(&:total_requests) + current_hour_total
            current_week_errors = current_week_stats.sum(&:error_count) + current_hour_errors
            current_week_rate = current_week_requests > 0 ? (current_week_errors.to_f / current_week_requests * 100) : 0
            formatted_date = current_week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: current_week_rate.round(2) }
          end

          weekly_data
        end
      end
    end
  end
end