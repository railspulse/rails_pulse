module RailsPulse
  module Jobs
    module Tables
      class Index
        def initialize(ransack_query:, period_type: nil, start_time:, params:, disabled_tags: [], show_non_tagged: true, queue_name: nil)
          @ransack_query = ransack_query
          @period_type = period_type
          @start_time = start_time
          @params = params
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
          @queue_name = queue_name
        end

        def to_table
          # Check if we have explicit ransack sorts
          has_sorts = @ransack_query.sorts.any?

          # Store sorts for later and get result without ordering
          # This prevents PostgreSQL GROUP BY issues with ORDER BY columns
          base_query = @ransack_query.result(distinct: false).reorder(nil)
            .joins("INNER JOIN rails_pulse_jobs ON rails_pulse_jobs.id = rails_pulse_summaries.summarizable_id")
            .where(
              summarizable_type: "RailsPulse::Job",
              period_type: @period_type
            )

          # Apply tag filters by excluding jobs with disabled tags
          # Separate "non_tagged" from actual tags (it's a virtual tag)
          actual_disabled_tags = @disabled_tags.reject { |tag| tag == "non_tagged" }

          # Exclude jobs with actual disabled tags
          actual_disabled_tags.each do |tag|
            sanitized_tag = ActiveRecord::Base.sanitize_sql_like(tag.to_s, "\\")
            base_query = base_query.where.not("rails_pulse_jobs.tags LIKE ?", "%#{sanitized_tag}%")
          end

          # Exclude non-tagged jobs if show_non_tagged is false
          unless @show_non_tagged
            base_query = base_query.where("rails_pulse_jobs.tags IS NOT NULL AND rails_pulse_jobs.tags != '[]'")
          end

          # Apply queue filter if provided
          if @queue_name.present?
            base_query = base_query.where("rails_pulse_jobs.queue_name = ?", @queue_name)
          end

          # Apply grouping and aggregation
          grouped_query = base_query
            .group(
              "rails_pulse_summaries.summarizable_id",
              "rails_pulse_summaries.summarizable_type",
              "rails_pulse_jobs.id",
              "rails_pulse_jobs.name",
              "rails_pulse_jobs.queue_name",
              "rails_pulse_jobs.tags"
            )
            .select(
              "rails_pulse_summaries.summarizable_id",
              "rails_pulse_summaries.summarizable_type",
              "rails_pulse_jobs.id as job_id",
              "rails_pulse_jobs.name",
              "rails_pulse_jobs.queue_name",
              "rails_pulse_jobs.tags",
              "AVG(rails_pulse_summaries.avg_duration) as avg_duration",
              "MAX(rails_pulse_summaries.max_duration) as max_duration",
              "SUM(rails_pulse_summaries.p95_duration * rails_pulse_summaries.count) / NULLIF(SUM(rails_pulse_summaries.count), 0) as p95_duration",
              "SUM(rails_pulse_summaries.p99_duration * rails_pulse_summaries.count) / NULLIF(SUM(rails_pulse_summaries.count), 0) as p99_duration",
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
            when "name"
              grouped_query = grouped_query.order(Arel.sql("rails_pulse_jobs.name").send(direction))
            when "queue_name"
              grouped_query = grouped_query.order(Arel.sql("rails_pulse_jobs.queue_name").send(direction))
            when "avg_duration_sort"
              grouped_query = grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").send(direction))
            when "max_duration_sort"
              grouped_query = grouped_query.order(Arel.sql("MAX(rails_pulse_summaries.max_duration)").send(direction))
            when "p95_duration_sort"
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.p95_duration * rails_pulse_summaries.count) / NULLIF(SUM(rails_pulse_summaries.count), 0)").send(direction))
            when "p99_duration_sort"
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.p99_duration * rails_pulse_summaries.count) / NULLIF(SUM(rails_pulse_summaries.count), 0)").send(direction))
            when "count_sort", "runs_count_sort"
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count)").send(direction))
            when "failures_count_sort", "error_count_sort"
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.error_count)").send(direction))
            else
              # Unknown sort field, fallback to default
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count)").desc)
            end
          else
            # Apply default sort when no explicit sort is provided
            grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count)").desc)
          end

          grouped_query
        end
      end
    end
  end
end
