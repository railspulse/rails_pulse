module RailsPulse
  module Queries
    module Tables
      class Index < RailsPulse::Tables::Base
        def initialize(query: nil, **kwargs)
          super(**kwargs)
          @query = query
        end

        private

        def apply_extra_filters(query)
          @query ? query.where(summarizable_id: @query.id) : query
        end

        def join_clause
          "INNER JOIN rails_pulse_queries ON rails_pulse_queries.id = rails_pulse_summaries.summarizable_id"
        end

        def summarizable_type = "RailsPulse::Query"
        def model_table = "rails_pulse_queries"

        def group_columns
          %w[
            rails_pulse_summaries.summarizable_id
            rails_pulse_summaries.summarizable_type
            rails_pulse_queries.id
            rails_pulse_queries.normalized_sql
            rails_pulse_queries.tags
          ]
        end

        def select_columns
          [
            "rails_pulse_summaries.summarizable_id",
            "rails_pulse_summaries.summarizable_type",
            "rails_pulse_queries.id as query_id",
            "rails_pulse_queries.normalized_sql",
            "rails_pulse_queries.tags",
            "AVG(rails_pulse_summaries.avg_duration) as avg_duration",
            "MAX(rails_pulse_summaries.max_duration) as max_duration",
            "#{WEIGHTED_P95} as p95_duration",
            "#{WEIGHTED_P99} as p99_duration",
            "SUM(rails_pulse_summaries.count) as execution_count",
            "SUM(rails_pulse_summaries.count * rails_pulse_summaries.avg_duration) as total_time_consumed"
          ]
        end

        def named_sort(grouped_query, sort_name, direction)
          case sort_name
          when "avg_duration_sort"
            grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").send(direction))
          when "p95_duration_sort"
            grouped_query.order(Arel.sql(WEIGHTED_P95).send(direction))
          when "p99_duration_sort"
            grouped_query.order(Arel.sql(WEIGHTED_P99).send(direction))
          when "execution_count_sort"
            grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count)").send(direction))
          when "total_time_consumed_sort"
            grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count * rails_pulse_summaries.avg_duration)").send(direction))
          when "normalized_sql"
            grouped_query.order(Arel.sql("rails_pulse_queries.normalized_sql").send(direction))
          end
        end

        def default_sort = Arel.sql("AVG(rails_pulse_summaries.p95_duration)").desc
      end
    end
  end
end
