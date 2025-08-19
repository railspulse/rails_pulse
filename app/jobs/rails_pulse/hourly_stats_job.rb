module RailsPulse
  class HourlyStatsJob < ApplicationJob
    queue_as :default

    def perform(target_hour = nil)
      target_hour ||= (Time.current - 1.hour).beginning_of_hour
      target_hour = target_hour.utc

      Rails.logger.info "[RailsPulse::HourlyStatsJob] Starting hourly stats generation for #{target_hour}"

      route_stats = process_routes_for_hour(target_hour)
      request_stats = process_requests_for_hour(target_hour)
      query_stats = process_queries_for_hour(target_hour)

      Rails.logger.info "[RailsPulse::HourlyStatsJob] Completed - #{route_stats[:routes_processed]} routes, #{request_stats[:requests_processed]} requests, #{query_stats[:queries_processed]} queries processed for hour #{target_hour.hour}"

      {
        routes: route_stats,
        requests: request_stats,
        queries: query_stats
      }
    rescue => e
      Rails.logger.error "[RailsPulse::HourlyStatsJob] Failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end

    private

    def process_routes_for_hour(target_hour)
      date = target_hour.to_date
      hour = target_hour.hour
      hour_end = target_hour + 1.hour

      routes_processed = 0

      # Process each route that had requests in this hour
      route_ids_with_requests = RailsPulse::Request
        .where(occurred_at: target_hour..hour_end)
        .distinct
        .pluck(:route_id)

      route_ids_with_requests.each do |route_id|
        process_route_hour(route_id, date, hour, target_hour, hour_end)
        routes_processed += 1
      end

      { routes_processed: routes_processed, hour: hour, date: date }
    end

    def process_route_hour(route_id, date, hour, hour_start, hour_end)
      # Get all requests for this route in this hour
      requests = RailsPulse::Request
        .where(route_id: route_id, occurred_at: hour_start...hour_end)

      return if requests.empty?

      # Calculate hourly stats
      total_requests = requests.count
      durations = requests.pluck(:duration)
      error_count = requests.where(is_error: true).count

      hourly_data = {
        requests: total_requests,
        avg_duration: durations.empty? ? 0.0 : (durations.sum.to_f / durations.size).round(3),
        max_duration: durations.max || 0.0,
        errors: error_count,
        p95_duration: calculate_p95(durations)
      }

      # Upsert the daily stat record with this hour's data
      RailsPulse::DailyStat.upsert_hourly_data(
        date: date,
        entity_type: "route",
        entity_id: route_id,
        hour: hour,
        data: hourly_data
      )
    end

    def process_requests_for_hour(target_hour)
      date = target_hour.to_date
      hour = target_hour.hour
      hour_end = target_hour + 1.hour

      # Get all requests in this hour (no grouping by route)
      requests = RailsPulse::Request
        .where(occurred_at: target_hour...hour_end)

      return { requests_processed: 0, hour: hour, date: date } if requests.empty?

      # Calculate hourly stats for all requests
      total_requests = requests.count
      durations = requests.pluck(:duration)
      error_count = requests.where(is_error: true).count

      hourly_data = {
        requests: total_requests,
        avg_duration: durations.empty? ? 0.0 : (durations.sum.to_f / durations.size).round(3),
        max_duration: durations.max || 0.0,
        errors: error_count,
        p95_duration: calculate_p95(durations)
      }

      # Upsert the daily stat record for requests entity
      RailsPulse::DailyStat.upsert_hourly_data(
        date: date,
        entity_type: "request",
        entity_id: nil, # No specific entity_id for aggregate requests
        hour: hour,
        data: hourly_data
      )

      { requests_processed: 1, hour: hour, date: date }
    end

    def process_queries_for_hour(target_hour)
      date = target_hour.to_date
      hour = target_hour.hour
      hour_end = target_hour + 1.hour

      queries_processed = 0

      # Process each query that had operations in this hour (skip operations with nil query_id)
      query_ids_with_operations = RailsPulse::Operation
        .where(occurred_at: target_hour...hour_end)
        .where.not(query_id: nil)
        .distinct
        .pluck(:query_id)

      query_ids_with_operations.each do |query_id|
        process_query_hour(query_id, date, hour, target_hour, hour_end)
        queries_processed += 1
      end

      { queries_processed: queries_processed, hour: hour, date: date }
    end

    def process_query_hour(query_id, date, hour, hour_start, hour_end)
      # Get all operations for this query in this hour
      operations = RailsPulse::Operation
        .where(query_id: query_id, occurred_at: hour_start...hour_end)

      return if operations.empty?

      # Calculate hourly stats
      total_operations = operations.count
      durations = operations.pluck(:duration)

      hourly_data = {
        requests: total_operations, # Using 'requests' field for consistency with route stats
        avg_duration: durations.empty? ? 0.0 : (durations.sum.to_f / durations.size).round(3),
        max_duration: durations.max || 0.0,
        errors: 0, # Operations don't have error tracking like requests
        p95_duration: calculate_p95(durations)
      }

      # Upsert the daily stat record with this hour's data
      RailsPulse::DailyStat.upsert_hourly_data(
        date: date,
        entity_type: "query",
        entity_id: query_id,
        hour: hour,
        data: hourly_data
      )
    end

    def calculate_p95(durations)
      return 0.0 if durations.empty?

      sorted = durations.sort
      index = (sorted.length * 0.95).ceil - 1
      sorted[index].to_f
    end
  end
end
