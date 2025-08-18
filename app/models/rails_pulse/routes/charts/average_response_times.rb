module RailsPulse
  module Routes
    module Charts
      class AverageResponseTimes
        def initialize(ransack_query:, group_by: :group_by_day, route: nil)
          @ransack_query = ransack_query
          @group_by = group_by
          @route = route
        end

        def to_rails_chart
          # Use hybrid approach: daily stats for historical data, raw data for current hour
          if daily_stats_available? && should_use_daily_stats?
            build_chart_from_daily_stats
          else
            build_chart_from_raw_data
          end
        end

        private

        def daily_stats_available?
          # Check if we have reasonable daily stats coverage
          route_filter = @route ? [ @route.id ] : RailsPulse::Route.pluck(:id)
          return false if route_filter.empty?

          stats_count = RailsPulse::DailyStat
            .where(entity_type: "route", entity_id: route_filter)
            .where(date: 7.days.ago.to_date..Date.current)
            .count
          stats_count >= 5 # Need reasonable coverage
        end

        def should_use_daily_stats?
          # For now, use daily stats for both daily and hourly grouping
          # since we store hourly data in the daily stats JSON field
          true
        end

        def build_chart_from_daily_stats
          chart_data = {}
          current_hour_start = Time.current.beginning_of_hour.utc

          # Get the time range from ransack query
          time_range = extract_time_range_from_query

          if @group_by == :group_by_day
            build_daily_chart_from_stats(chart_data, time_range)
          else
            build_hourly_chart_from_stats(chart_data, time_range, current_hour_start)
          end

          chart_data
        end

        def build_chart_from_raw_data
          # Fallback to original raw data approach
          actual_data = if @route
            @ransack_query.result(distinct: false)
              .public_send(@group_by, "occurred_at", series: true, time_zone: "UTC")
              .average(:duration)
          else
            @ransack_query.result(distinct: false)
              .left_joins(:requests)
              .public_send(@group_by, "rails_pulse_requests.occurred_at", series: true, time_zone: "UTC")
              .average("rails_pulse_requests.duration")
          end

          # Convert to the format expected by rails_charts
          actual_data.transform_keys do |k|
            if k.respond_to?(:to_i)
              k.to_i
            else
              # For Date objects, use beginning_of_day to get consistent UTC timestamps
              k.is_a?(Date) ? k.beginning_of_day.to_i : k.to_time.to_i
            end
          end.transform_values { |v| { value: v.to_f } }
        end

        def extract_time_range_from_query
          # Extract time range from ransack query conditions
          conditions = @ransack_query.conditions
          start_time = nil
          end_time = nil

          conditions.each do |condition|
            case condition.predicate.name
            when "gteq", "gt"
              if condition.attributes.first&.name&.include?("occurred_at")
                value = condition.values.first
                start_time = value.respond_to?(:value) ? value.value : value
              end
            when "lteq", "lt"
              if condition.attributes.first&.name&.include?("occurred_at")
                value = condition.values.first
                end_time = value.respond_to?(:value) ? value.value : value
              end
            end
          end

          # Ensure we have Time objects
          start_time = start_time.is_a?(String) ? Time.parse(start_time) : start_time
          end_time = end_time.is_a?(String) ? Time.parse(end_time) : end_time

          {
            start: start_time || 7.days.ago.beginning_of_day,
            end: end_time || Time.current
          }
        end

        def build_daily_chart_from_stats(chart_data, time_range)
          # Get daily stats for the time range
          route_ids = @route ? [ @route.id ] : RailsPulse::Route.pluck(:id)

          daily_stats = RailsPulse::DailyStat
            .where(entity_type: "route", entity_id: route_ids)
            .where(date: time_range[:start].to_date..time_range[:end].to_date)
            .where("total_requests > 0")

          if @route
            # Single route - use daily averages directly
            daily_stats.each do |stat|
              timestamp = stat.date.beginning_of_day.to_i
              chart_data[timestamp] = { value: stat.avg_duration.to_f }
            end
          else
            # Multiple routes - group by date and calculate weighted average
            daily_stats.group_by(&:date).each do |date, stats|
              total_requests = stats.sum(&:total_requests)
              if total_requests > 0
                weighted_avg = stats.sum { |s| s.total_requests * s.avg_duration } / total_requests
                timestamp = date.beginning_of_day.to_i
                chart_data[timestamp] = { value: weighted_avg.to_f }
              end
            end
          end

          # Add current day data from raw data if needed
          add_current_day_data(chart_data, time_range)
        end

        def build_hourly_chart_from_stats(chart_data, time_range, current_hour_start)
          # Get daily stats with hourly data
          route_ids = @route ? [ @route.id ] : RailsPulse::Route.pluck(:id)

          daily_stats = RailsPulse::DailyStat
            .where(entity_type: "route", entity_id: route_ids)
            .where(date: time_range[:start].to_date..time_range[:end].to_date)
            .where("hourly_data IS NOT NULL")

          daily_stats.each do |stat|
            next unless stat.has_hourly_data?

            stat.completed_hours.each do |hour|
              hour_data = stat.hourly_breakdown_for(hour)
              next unless hour_data["requests"].to_i > 0

              hour_time = stat.date.beginning_of_day + hour.hours

              # Check if this hour falls within our time range
              next if hour_time < time_range[:start] || hour_time >= time_range[:end]

              timestamp = hour_time.to_i

              if @route
                # Single route
                chart_data[timestamp] = { value: hour_data["avg_duration"].to_f }
              else
                # Multiple routes - we need to aggregate across routes for this hour
                if chart_data[timestamp]
                  # Weighted average with existing data
                  existing_requests = chart_data[timestamp][:requests] || 0
                  existing_duration = chart_data[timestamp][:weighted_duration] || 0
                  new_requests = hour_data["requests"].to_i
                  new_duration = hour_data["requests"].to_i * hour_data["avg_duration"].to_f

                  total_requests = existing_requests + new_requests
                  total_duration = existing_duration + new_duration

                  chart_data[timestamp] = {
                    value: total_requests > 0 ? (total_duration / total_requests) : 0,
                    requests: total_requests,
                    weighted_duration: total_duration
                  }
                else
                  chart_data[timestamp] = {
                    value: hour_data["avg_duration"].to_f,
                    requests: hour_data["requests"].to_i,
                    weighted_duration: hour_data["requests"].to_i * hour_data["avg_duration"].to_f
                  }
                end
              end
            end
          end

          # Add current hour from raw data
          add_current_hour_data(chart_data, current_hour_start)

          # Clean up helper fields for multi-route aggregation
          unless @route
            chart_data.each do |timestamp, data|
              chart_data[timestamp] = { value: data[:value] }
            end
          end
        end

        def add_current_day_data(chart_data, time_range)
          today = Date.current
          return unless time_range[:start].to_date <= today && today <= time_range[:end].to_date

          # Get today's data from raw requests
          current_day_requests = if @route
            RailsPulse::Request.where(route: @route, occurred_at: today.beginning_of_day..today.end_of_day)
          else
            RailsPulse::Request.where(occurred_at: today.beginning_of_day..today.end_of_day)
          end

          avg_duration = current_day_requests.average(:duration)
          if avg_duration
            timestamp = today.beginning_of_day.to_i
            chart_data[timestamp] = { value: avg_duration.to_f }
          end
        end

        def add_current_hour_data(chart_data, current_hour_start)
          # Get current hour data from raw requests
          current_hour_requests = if @route
            RailsPulse::Request.where(route: @route, occurred_at: current_hour_start...(current_hour_start + 1.hour))
          else
            RailsPulse::Request.where(occurred_at: current_hour_start...(current_hour_start + 1.hour))
          end

          avg_duration = current_hour_requests.average(:duration)
          if avg_duration
            timestamp = current_hour_start.to_i
            chart_data[timestamp] = { value: avg_duration.to_f }
          end
        end
      end
    end
  end
end
