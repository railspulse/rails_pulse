module RailsPulse
  module Jobs
    module Tables
      class Index < RailsPulse::Tables::Base
        def initialize(queue_name: nil, **kwargs)
          super(**kwargs)
          @queue_name = queue_name
        end

        private

        def apply_extra_filters(query)
          @queue_name.present? ? query.where("rails_pulse_jobs.queue_name = ?", @queue_name) : query
        end

        def join_clause
          "INNER JOIN rails_pulse_jobs ON rails_pulse_jobs.id = rails_pulse_summaries.summarizable_id"
        end

        def summarizable_type = "RailsPulse::Job"
        def model_table = "rails_pulse_jobs"

        def group_columns
          %w[
            rails_pulse_summaries.summarizable_id
            rails_pulse_summaries.summarizable_type
            rails_pulse_jobs.id
            rails_pulse_jobs.name
            rails_pulse_jobs.queue_name
            rails_pulse_jobs.tags
          ]
        end

        def select_columns
          [
            "rails_pulse_summaries.summarizable_id",
            "rails_pulse_summaries.summarizable_type",
            "rails_pulse_jobs.id as job_id",
            "rails_pulse_jobs.name",
            "rails_pulse_jobs.queue_name",
            "rails_pulse_jobs.tags",
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
          when "name"
            grouped_query.order(Arel.sql("rails_pulse_jobs.name").send(direction))
          when "queue_name"
            grouped_query.order(Arel.sql("rails_pulse_jobs.queue_name").send(direction))
          when "avg_duration_sort"
            grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").send(direction))
          when "max_duration_sort"
            grouped_query.order(Arel.sql("MAX(rails_pulse_summaries.max_duration)").send(direction))
          when "p95_duration_sort"
            grouped_query.order(Arel.sql(WEIGHTED_P95).send(direction))
          when "p99_duration_sort"
            grouped_query.order(Arel.sql(WEIGHTED_P99).send(direction))
          when "count_sort", "runs_count_sort"
            grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count)").send(direction))
          when "failures_count_sort", "error_count_sort"
            grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.error_count)").send(direction))
          end
        end

        def default_sort = Arel.sql("SUM(rails_pulse_summaries.count)").desc
      end
    end
  end
end
