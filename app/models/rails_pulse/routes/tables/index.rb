module RailsPulse
  module Routes
    module Tables
      class Index < RailsPulse::Tables::Base
        private

        def join_clause
          "INNER JOIN rails_pulse_routes ON rails_pulse_routes.id = rails_pulse_summaries.summarizable_id"
        end

        def summarizable_type = "RailsPulse::Route"
        def model_table = "rails_pulse_routes"

        def group_columns
          %w[
            rails_pulse_summaries.summarizable_id
            rails_pulse_summaries.summarizable_type
            rails_pulse_routes.id
            rails_pulse_routes.path
            rails_pulse_routes.method
            rails_pulse_routes.tags
          ]
        end

        def select_columns
          [
            "rails_pulse_summaries.summarizable_id",
            "rails_pulse_summaries.summarizable_type",
            "rails_pulse_routes.id as route_id",
            "rails_pulse_routes.path",
            "rails_pulse_routes.method as route_method",
            "rails_pulse_routes.tags",
            "AVG(rails_pulse_summaries.avg_duration) as avg_duration",
            "MAX(rails_pulse_summaries.max_duration) as max_duration",
            "#{WEIGHTED_P95} as p95_duration",
            "#{WEIGHTED_P99} as p99_duration",
            "SUM(rails_pulse_summaries.count) as count",
            "SUM(rails_pulse_summaries.error_count) as error_count",
            "SUM(rails_pulse_summaries.success_count) as success_count"
          ]
        end

        def named_sort(grouped_query, sort_name, direction)
          case sort_name
          when "avg_duration_sort"
            grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").send(direction))
          when "max_duration_sort"
            grouped_query.order(Arel.sql("MAX(rails_pulse_summaries.max_duration)").send(direction))
          when "p95_duration_sort"
            grouped_query.order(Arel.sql(WEIGHTED_P95).send(direction))
          when "p99_duration_sort"
            grouped_query.order(Arel.sql(WEIGHTED_P99).send(direction))
          when "count_sort", "request_count_sort"
            grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count)").send(direction))
          when "requests_per_minute"
            grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count) / 60.0").send(direction))
          when "error_rate_percentage"
            grouped_query.order(Arel.sql("(SUM(rails_pulse_summaries.error_count) * 100.0) / SUM(rails_pulse_summaries.count)").send(direction))
          when "route_path"
            grouped_query.order(Arel.sql("rails_pulse_routes.path").send(direction))
          end
        end

        def default_sort = Arel.sql("AVG(rails_pulse_summaries.p95_duration)").desc
      end
    end
  end
end
