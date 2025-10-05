module RailsPulse
  module Routes
    module Tables
      class Index
        def initialize(ransack_query:, period_type: nil, start_time:, params:)
          @ransack_query = ransack_query
          @period_type = period_type
          @start_time = start_time
          @params = params
        end

        def to_table
          # Check if we have explicit ransack sorts
          has_sorts = @ransack_query.sorts.any?

          # Store sorts for later and get result without ordering
          # This prevents PostgreSQL GROUP BY issues with ORDER BY columns
          base_query = @ransack_query.result(distinct: false).reorder(nil)
            .joins("INNER JOIN rails_pulse_routes ON rails_pulse_routes.id = rails_pulse_summaries.summarizable_id")
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: @period_type
            )

          base_query = base_query.where(summarizable_id: @route.id) if @route

          # Apply grouping and aggregation
          grouped_query = base_query
            .group(
              "rails_pulse_summaries.summarizable_id",
              "rails_pulse_summaries.summarizable_type",
              "rails_pulse_routes.id",
              "rails_pulse_routes.path",
              "rails_pulse_routes.method"
            )
            .select(
              "rails_pulse_summaries.summarizable_id",
              "rails_pulse_summaries.summarizable_type",
              "rails_pulse_routes.id as route_id",
              "rails_pulse_routes.path",
              "rails_pulse_routes.method as route_method",
              "AVG(rails_pulse_summaries.avg_duration) as avg_duration",
              "MAX(rails_pulse_summaries.max_duration) as max_duration",
              "SUM(rails_pulse_summaries.count) as count",
              "SUM(rails_pulse_summaries.error_count) as error_count",
              "SUM(rails_pulse_summaries.success_count) as success_count"
            )

          # Apply sorting based on ransack sorts or use default
          if has_sorts
            # Apply custom sorting based on ransack parameters
            sort = @ransack_query.sorts.first
            direction = sort.dir == "desc" ? :desc : :asc

            case sort.name
            when "avg_duration_sort"
              grouped_query = grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").send(direction))
            when "max_duration_sort"
              grouped_query = grouped_query.order(Arel.sql("MAX(rails_pulse_summaries.max_duration)").send(direction))
            when "count_sort", "request_count_sort"
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count)").send(direction))
            when "requests_per_minute"
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count) / 60.0").send(direction))
            when "error_rate_percentage"
              grouped_query = grouped_query.order(Arel.sql("(SUM(rails_pulse_summaries.error_count) * 100.0) / SUM(rails_pulse_summaries.count)").send(direction))
            when "route_path"
              grouped_query = grouped_query.order(Arel.sql("rails_pulse_routes.path").send(direction))
            else
              # Unknown sort field, fallback to default
              grouped_query = grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").desc)
            end
          else
            # Apply default sort when no explicit sort is provided (matches controller default_table_sort)
            grouped_query = grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").desc)
          end

          grouped_query
        end
      end
    end
  end
end
