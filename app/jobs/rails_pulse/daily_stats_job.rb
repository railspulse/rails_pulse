module RailsPulse
  class DailyStatsJob < ApplicationJob
    queue_as :default

    def perform(target_date = nil)
      target_date ||= Date.current - 1.day
      target_date = target_date.to_date

      Rails.logger.info "[RailsPulse::DailyStatsJob] Starting daily aggregation for #{target_date}"

      route_stats = process_routes_daily_aggregates(target_date)
      request_stats = process_requests_daily_aggregates(target_date)
      query_stats = process_queries_daily_aggregates(target_date)

      Rails.logger.info "[RailsPulse::DailyStatsJob] Completed - #{route_stats[:routes_finalized]} routes, #{request_stats[:requests_finalized]} requests, #{query_stats[:queries_finalized]} queries finalized for #{target_date}"

      {
        routes: route_stats,
        requests: request_stats,
        queries: query_stats
      }
    rescue => e
      Rails.logger.error "[RailsPulse::DailyStatsJob] Failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end

    private

    def process_routes_daily_aggregates(target_date)
      routes_finalized = 0

      # Find all daily stat records for this date that need daily aggregates
      daily_stats = RailsPulse::DailyStat
        .where(date: target_date, entity_type: "route")
        .where(total_requests: 0) # Only records that haven't been finalized yet

      daily_stats.find_each do |daily_stat|
        finalize_route_daily_aggregates(daily_stat, target_date)
        routes_finalized += 1
      end

      { routes_finalized: routes_finalized, date: target_date }
    end

    def process_requests_daily_aggregates(target_date)
      requests_finalized = 0

      # Find all daily stat records for requests that need daily aggregates
      daily_stats = RailsPulse::DailyStat
        .where(date: target_date, entity_type: "request")
        .where(total_requests: 0)

      daily_stats.find_each do |daily_stat|
        finalize_request_daily_aggregates(daily_stat, target_date)
        requests_finalized += 1
      end

      { requests_finalized: requests_finalized, date: target_date }
    end

    def process_queries_daily_aggregates(target_date)
      queries_finalized = 0

      # Find all daily stat records for queries that need daily aggregates (skip nil entity_id)
      daily_stats = RailsPulse::DailyStat
        .where(date: target_date, entity_type: "query")
        .where.not(entity_id: nil)
        .where(total_requests: 0)

      daily_stats.find_each do |daily_stat|
        finalize_query_daily_aggregates(daily_stat, target_date)
        queries_finalized += 1
      end

      { queries_finalized: queries_finalized, date: target_date }
    end

    def finalize_route_daily_aggregates(daily_stat, target_date)
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

    def finalize_request_daily_aggregates(daily_stat, target_date)
      # Get all requests on this date (no specific entity_id for aggregate requests)
      day_start = target_date.beginning_of_day.utc
      day_end = target_date.end_of_day.utc

      requests = RailsPulse::Request
        .where(occurred_at: day_start..day_end)

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

    def finalize_query_daily_aggregates(daily_stat, target_date)
      query_id = daily_stat.entity_id

      # Get all operations for this query on this date
      day_start = target_date.beginning_of_day.utc
      day_end = target_date.end_of_day.utc

      operations = RailsPulse::Operation
        .where(query_id: query_id, occurred_at: day_start..day_end)

      return if operations.empty?

      # Calculate daily aggregates from raw data
      total_operations = operations.count
      durations = operations.pluck(:duration)

      aggregates = {
        total_requests: total_operations, # Using same field name for consistency
        avg_duration: durations.empty? ? 0.0 : (durations.sum.to_f / durations.size).round(3),
        max_duration: durations.max || 0.0,
        error_count: 0, # Operations don't have error tracking
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
