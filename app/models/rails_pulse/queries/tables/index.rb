module RailsPulse
  module Queries
    module Tables
      class Index
        def initialize(ransack_query:, period_type: nil, start_time:, params:, query: nil, disabled_tags: [])
          @ransack_query = ransack_query
          @period_type = period_type
          @start_time = start_time
          @params = params
          @query = query
          @disabled_tags = disabled_tags
        end

        def to_table
          # Check if we have explicit ransack sorts
          has_sorts = @ransack_query.sorts.any?

          base_query = @ransack_query.result(distinct: false)
            .joins("INNER JOIN rails_pulse_queries ON rails_pulse_queries.id = rails_pulse_summaries.summarizable_id")
            .where(
              summarizable_type: "RailsPulse::Query",
              period_type: @period_type
            )

          # Apply tag filters by excluding queries with disabled tags
          @disabled_tags.each do |tag|
            base_query = base_query.where.not("rails_pulse_queries.tags LIKE ?", "%#{tag}%")
          end

          base_query = base_query.where(summarizable_id: @query.id) if @query

          # Apply grouping and aggregation
          grouped_query = base_query
            .group(
              "rails_pulse_summaries.summarizable_id",
              "rails_pulse_summaries.summarizable_type",
              "rails_pulse_queries.id",
              "rails_pulse_queries.normalized_sql",
              "rails_pulse_queries.tags"
            )
            .select(
              "rails_pulse_summaries.summarizable_id",
              "rails_pulse_summaries.summarizable_type",
              "rails_pulse_queries.id as query_id",
              "rails_pulse_queries.normalized_sql",
              "rails_pulse_queries.tags",
              "AVG(rails_pulse_summaries.avg_duration) as avg_duration",
              "MAX(rails_pulse_summaries.max_duration) as max_duration",
              "SUM(rails_pulse_summaries.count) as execution_count",
              "SUM(rails_pulse_summaries.count * rails_pulse_summaries.avg_duration) as total_time_consumed"
            )

          # Apply sorting based on ransack sorts or use default
          if has_sorts
            # Apply custom sorting based on ransack parameters
            sort = @ransack_query.sorts.first
            direction = sort.dir == "desc" ? :desc : :asc

            case sort.name
            when "avg_duration_sort"
              grouped_query = grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").send(direction))
            when "execution_count_sort"
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count)").send(direction))
            when "total_time_consumed_sort"
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count * rails_pulse_summaries.avg_duration)").send(direction))
            when "normalized_sql"
              grouped_query = grouped_query.order(Arel.sql("rails_pulse_queries.normalized_sql").send(direction))
            else
              # Unknown sort field, fallback to default
              grouped_query = grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").desc)
            end
          else
            # Apply default sort when no explicit sort is provided
            grouped_query = grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").desc)
          end

          grouped_query
        end
      end
    end
  end
end
