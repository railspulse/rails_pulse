module RailsPulse
  module Queries
    module Cards
      class PercentileQueryTimes
        def initialize(query: nil)
          @query = query
        end

        def to_metric_card
          # Use daily stats for performance, fall back to raw data if needed
          percentile_95th, current_period_95th, previous_period_95th, sparkline_data =
            if daily_stats_available?
              calculate_from_daily_stats
            else
              calculate_from_raw_data
            end

          percentage = previous_period_95th.zero? ?  0 : ((previous_period_95th - current_period_95th) / previous_period_95th * 100).abs.round(1)
          trend_icon = percentage < 0.1 ?  "move-right" : current_period_95th < previous_period_95th ? "trending-down" : "trending-up"
          trend_amount = previous_period_95th.zero? ? "0%" : "#{percentage}%"

          {
            title: "95th Percentile Query Time",
            summary: "#{percentile_95th.round(0)} ms",
            line_chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week"
          }
        end

        private

        def daily_stats_available?
          # Check if we have daily stats for queries entity
          query_filter = @query ? [@query.id] : RailsPulse::Query.pluck(:id)
          return false if query_filter.empty?

          stats_count = RailsPulse::DailyStat
            .where(entity_type: "query", entity_id: query_filter)
            .where(date: 7.days.ago.to_date..Date.current)
            .count
          stats_count >= 5 # Need reasonable coverage
        end

        def calculate_from_daily_stats
          # Get daily stats for the last 2 weeks
          query_filter = @query ? [@query.id] : RailsPulse::Query.pluck(:id)

          daily_stats = RailsPulse::DailyStat
            .where(entity_type: "query", entity_id: query_filter)
            .for_date_range(14.days.ago.to_date, Date.current)
            .where("total_requests > 0") # Only finalized stats

          # Calculate overall p95 from daily stats (weighted average of p95s)
          total_requests = daily_stats.sum(:total_requests)
          weighted_p95_sum = daily_stats.sum { |stat| stat.total_requests * stat.p95_duration }
          
          # Add current hour raw data for real-time accuracy
          current_hour_p95, current_hour_count = get_current_hour_percentile_data
          if current_hour_count > 0
            total_requests += current_hour_count
            weighted_p95_sum += current_hour_count * current_hour_p95
          end

          percentile_95th = total_requests > 0 ? weighted_p95_sum / total_requests : 0

          # Calculate trend (last 7 days vs previous 7 days)
          last_7_days_stats = daily_stats.where(date: 7.days.ago.to_date..Date.current)
          previous_7_days_stats = daily_stats.where(date: 14.days.ago.to_date...7.days.ago.to_date)

          # Current period weighted p95
          current_requests = last_7_days_stats.sum(:total_requests) + current_hour_count
          current_p95_sum = last_7_days_stats.sum { |s| s.total_requests * s.p95_duration } + (current_hour_count * current_hour_p95)
          current_period_95th = current_requests > 0 ? current_p95_sum / current_requests : 0

          # Previous period weighted p95
          previous_requests = previous_7_days_stats.sum(:total_requests)
          previous_p95_sum = previous_7_days_stats.sum { |s| s.total_requests * s.p95_duration }
          previous_period_95th = previous_requests > 0 ? previous_p95_sum / previous_requests : 0

          # Create sparkline data by week using p95 from daily stats
          sparkline_data = build_sparkline_from_daily_stats(daily_stats, current_hour_p95, current_hour_count)

          [percentile_95th, current_period_95th, previous_period_95th, sparkline_data]
        end

        def calculate_from_raw_data
          # Fallback to original raw data approach
          operations = if @query
            RailsPulse::Operation.where(query: @query)
          else
            RailsPulse::Operation.all
          end

          # Calculate overall 95th percentile response time
          count = operations.count
          percentile_95th = if count > 0
            operations.select("duration").order("duration").limit(1).offset((count * 0.95).floor).pluck(:duration).first || 0
          else
            0
          end

          # Calculate trend by comparing last 7 days vs previous 7 days for 95th percentile
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          current_period = operations.where("occurred_at >= ?", last_7_days)
          current_count = current_period.count
          current_period_95th = if current_count > 0
            current_period.select("duration").order("duration").limit(1).offset((current_count * 0.95).floor).pluck(:duration).first || 0
          else
            0
          end

          previous_period = operations.where("occurred_at >= ? AND occurred_at < ?", previous_7_days, last_7_days)
          previous_count = previous_period.count
          previous_period_95th = if previous_count > 0
            previous_period.select("duration").order("duration").limit(1).offset((previous_count * 0.95).floor).pluck(:duration).first || 0
          else
            0
          end

          sparkline_data = operations
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

        def get_current_hour_percentile_data
          current_hour_start = Time.current.beginning_of_hour.utc
          current_hour_end = current_hour_start + 1.hour

          operations = if @query
            RailsPulse::Operation.where(query: @query, occurred_at: current_hour_start...current_hour_end)
          else
            RailsPulse::Operation.where(occurred_at: current_hour_start...current_hour_end)
          end

          count = operations.count
          p95_duration = if count > 0
            operations.select("duration").order("duration").limit(1).offset((count * 0.95).floor).pluck(:duration).first || 0
          else
            0
          end

          [p95_duration, count]
        end

        def build_sparkline_from_daily_stats(daily_stats, current_hour_p95, current_hour_count)
          # Group by week for sparkline using p95 values
          weekly_data = {}

          daily_stats.group_by { |stat| stat.date.beginning_of_week }.each do |week_start, stats|
            total_requests = stats.sum(&:total_requests)
            total_p95_weighted = stats.sum { |s| s.total_requests * s.p95_duration }
            weekly_p95 = total_requests > 0 ? total_p95_weighted / total_requests : 0
            
            formatted_date = week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: weekly_p95.round(0) }
          end

          # Add current week data if we're in the current week
          current_week_start = Date.current.beginning_of_week
          if daily_stats.any? { |s| s.date >= current_week_start } || current_hour_count > 0
            current_week_stats = daily_stats.select { |s| s.date >= current_week_start }
            
            current_week_requests = current_week_stats.sum(&:total_requests) + current_hour_count
            current_week_p95_weighted = current_week_stats.sum { |s| s.total_requests * s.p95_duration } + (current_hour_count * current_hour_p95)
            current_week_p95 = current_week_requests > 0 ? current_week_p95_weighted / current_week_requests : 0
            
            formatted_date = current_week_start.strftime("%b %-d")
            weekly_data[formatted_date] = { value: current_week_p95.round(0) }
          end

          weekly_data
        end
      end
    end
  end
end
