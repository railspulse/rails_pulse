module RailsPulse
  class HourlyStatsJob < ApplicationJob
    queue_as :default

    def perform(target_hour = nil)
      target_hour ||= (Time.current - 1.hour).beginning_of_hour
      target_hour = target_hour.utc

      Rails.logger.info "[RailsPulse::HourlyStatsJob] Starting hourly stats generation for #{target_hour}"

      stats = process_routes_for_hour(target_hour)

      Rails.logger.info "[RailsPulse::HourlyStatsJob] Completed - #{stats[:routes_processed]} routes processed for hour #{target_hour.hour}"

      stats
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

    def calculate_p95(durations)
      return 0.0 if durations.empty?

      sorted = durations.sort
      index = (sorted.length * 0.95).ceil - 1
      sorted[index].to_f
    end
  end
end
