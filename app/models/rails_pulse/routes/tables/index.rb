module RailsPulse
  module Routes
    module Tables
      class Index
        def initialize(ransack_query:, start_time:, params:)
          @ransack_query = ransack_query
          @start_time = start_time
          @params = params
        end

        def to_table
          # Pre-calculate values to avoid SQL injection and improve readability
          minutes_elapsed = calculate_minutes_elapsed

          # Get thresholds with safe defaults to avoid nil access errors
          config = RailsPulse.configuration rescue nil
          thresholds = config&.route_thresholds || { slow: 500, very_slow: 1500, critical: 3000 }

          requests_per_minute_divisor = minutes_elapsed > 0 ? minutes_elapsed : 1

          status_sql = build_status_sql(thresholds)

          @ransack_query.result(distinct: false)
            .left_joins(:requests)
            .group("rails_pulse_routes.id")
            .select(
              "rails_pulse_routes.*",
              "COALESCE(AVG(rails_pulse_requests.duration), 0) AS average_response_time_ms",
              "COUNT(rails_pulse_requests.id) AS request_count",
              "COALESCE(COUNT(rails_pulse_requests.id) / #{requests_per_minute_divisor}, 0) AS requests_per_minute",
              "COALESCE(SUM(CASE WHEN rails_pulse_requests.is_error = true THEN 1 ELSE 0 END), 0) AS error_count",
              "CASE WHEN COUNT(rails_pulse_requests.id) > 0 THEN ROUND((COALESCE(SUM(CASE WHEN rails_pulse_requests.is_error = true THEN 1 ELSE 0 END), 0) * 100.0) / COUNT(rails_pulse_requests.id), 2) ELSE 0 END AS error_rate_percentage",
              "COALESCE(MAX(rails_pulse_requests.duration), 0) AS max_response_time_ms",
              "#{status_sql} AS status_indicator"
            )
        end

        private

        def calculate_minutes_elapsed
          start_timestamp = Time.at(@start_time.to_i).utc
          ((Time.current.utc - start_timestamp) / 60.0).round(2)
        end

        def build_status_sql(thresholds)
          # Ensure all thresholds have default values
          slow = thresholds[:slow] || 500
          very_slow = thresholds[:very_slow] || 1500
          critical = thresholds[:critical] || 3000

          <<-SQL.squish
            CASE
              WHEN COALESCE(AVG(rails_pulse_requests.duration), 0) >= #{critical} THEN 3
              WHEN COALESCE(AVG(rails_pulse_requests.duration), 0) >= #{very_slow} THEN 2
              WHEN COALESCE(AVG(rails_pulse_requests.duration), 0) >= #{slow} THEN 1
              ELSE 0
            END
          SQL
        end
      end
    end
  end
end
