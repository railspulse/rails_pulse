module RailsPulse
  class DailyStatsJob < ApplicationJob
    queue_as :default

    def perform(target_date = nil)
      target_date ||= Date.current - 1.day
      target_date = target_date.to_date

      Rails.logger.info "[RailsPulse::DailyStatsJob] Starting daily aggregation for #{target_date}"

      stats = process_daily_aggregates(target_date)

      Rails.logger.info "[RailsPulse::DailyStatsJob] Completed - #{stats[:routes_finalized]} routes finalized for #{target_date}"

      stats
    rescue => e
      Rails.logger.error "[RailsPulse::DailyStatsJob] Failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end

    private

    def process_daily_aggregates(target_date)
      routes_finalized = 0

      # Find all daily stat records for this date that need daily aggregates
      daily_stats = RailsPulse::DailyStat
        .where(date: target_date, entity_type: "route")
        .where(total_requests: 0) # Only records that haven't been finalized yet

      daily_stats.find_each do |daily_stat|
        finalize_daily_aggregates(daily_stat, target_date)
        routes_finalized += 1
      end

      { routes_finalized: routes_finalized, date: target_date }
    end

    def finalize_daily_aggregates(daily_stat, target_date)
      route_id = daily_stat.entity_id

      # Get all requests for this route on this date
      day_start = target_date.beginning_of_day.utc
      day_end = target_date.end_of_day.utc

      requests = RailsPulse::Request
        .where(route_id: route_id, occurred_at: day_start..day_end)

      return if requests.empty?

      # Calculate daily aggregates from raw data
      total_requests = requests.count
      durations = requests.pluck(:duration)
      error_count = requests.where(is_error: true).count

      aggregates = {
        total_requests: total_requests,
        avg_duration: durations.empty? ? 0.0 : (durations.sum.to_f / durations.size).round(3),
        max_duration: durations.max || 0.0,
        error_count: error_count,
        p95_duration: calculate_p95(durations)
      }

      # Update the daily stat record with final aggregates
      daily_stat.update!(aggregates)
    end

    def calculate_p95(durations)
      return 0.0 if durations.empty?

      sorted = durations.sort
      index = (sorted.length * 0.95).ceil - 1
      sorted[index].to_f
    end
  end
end
