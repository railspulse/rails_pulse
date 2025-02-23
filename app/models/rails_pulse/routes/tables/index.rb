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
          requests_per_minute_sql = <<-SQL.squish
            COALESCE(
              COUNT(rails_pulse_requests.id)*1.0
              / NULLIF(
                (julianday('now') - julianday(datetime(#{@start_time}, 'unixepoch'))) * 1440,
                0
              ),
              0
            )
          SQL

          # Use MAX() to show the worst-case response time for performance monitoring
          # Add status calculation based on thresholds
          slow_threshold = RailsPulse.configuration.route_thresholds[:slow]
          very_slow_threshold = RailsPulse.configuration.route_thresholds[:very_slow]
          critical_threshold = RailsPulse.configuration.route_thresholds[:critical]

          status_sql = <<-SQL.squish
            CASE 
              WHEN COALESCE(AVG(rails_pulse_requests.duration), 0) >= #{critical_threshold} THEN 3
              WHEN COALESCE(AVG(rails_pulse_requests.duration), 0) >= #{very_slow_threshold} THEN 2
              WHEN COALESCE(AVG(rails_pulse_requests.duration), 0) >= #{slow_threshold} THEN 1
              ELSE 0
            END
          SQL

          @ransack_query.result(distinct: false)
            .includes(:requests)
            .left_joins(:requests)
            .group("rails_pulse_routes.id")
            .select(
              "rails_pulse_routes.*",
              "COALESCE(AVG(rails_pulse_requests.duration), 0) AS average_response_time_ms",
              "COUNT(rails_pulse_requests.id) AS request_count",
              "#{requests_per_minute_sql} AS requests_per_minute",
              "COALESCE(SUM(CASE WHEN rails_pulse_requests.is_error = 1 THEN 1 ELSE 0 END), 0) AS error_count",
              "CASE WHEN COUNT(rails_pulse_requests.id) > 0 THEN ROUND((COALESCE(SUM(CASE WHEN rails_pulse_requests.is_error = 1 THEN 1 ELSE 0 END), 0) * 100.0) / COUNT(rails_pulse_requests.id), 2) ELSE 0 END AS error_rate_percentage",
              "COALESCE(MAX(rails_pulse_requests.duration), 0) AS max_response_time_ms",
              "#{status_sql} AS status_indicator"
            )
        end
      end
    end
  end
end
