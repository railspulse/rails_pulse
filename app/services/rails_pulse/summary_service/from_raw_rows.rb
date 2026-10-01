module RailsPulse
  class SummaryService
    # Summary rows for an hour, computed from raw requests, operations, job
    # runs and exception occurrences.
    #
    # Each route's, query's and job's rows are read separately, already
    # sorted by the database, so memory is bounded by the busiest one's hour
    # rather than by the whole hour's traffic. Percentiles are exact.
    #
    # Rows carry the summarizable and its metrics; SummaryService adds the
    # period columns.
    class FromRawRows
      def initialize(time_range)
        @time_range = time_range
      end

      # Always exactly one row, even for an empty hour (see SummaryService).
      def request_rows
        rows = Request.where(occurred_at: @time_range).order(:duration).pluck(:duration, :status)

        [
          row("RailsPulse::Request", 0)
            .merge(Metrics.duration(rows.map(&:first).compact), Metrics.status(rows.map(&:second)))
        ]
      end

      def route_rows
        scope = Request.where(occurred_at: @time_range)

        summarizable_ids(scope, :route_id).map do |route_id|
          rows = scope.where(route_id: route_id).order(:duration).pluck(:duration, :status)

          row("RailsPulse::Route", route_id).merge(
            Metrics.duration(rows.map(&:first).compact),
            Metrics.status(rows.map(&:second)),
            count: rows.size
          )
        end
      end

      def query_rows
        scope = Operation.where(occurred_at: @time_range)

        summarizable_ids(scope, :query_id).filter_map do |query_id|
          durations = scope.where(query_id: query_id).order(:duration).pluck(:duration).compact
          next if durations.empty?

          row("RailsPulse::Query", query_id).merge(Metrics.duration(durations))
        end
      end

      def job_rows
        scope = JobRun.where(occurred_at: @time_range).where(status: JobRun::FINAL_STATUSES)
        job_ids = summarizable_ids(scope, :job_id)
        return [] if job_ids.empty?

        # A run whose job row has gone (count-based cleanup) has nothing to
        # summarize against.
        known_job_ids = Job.where(id: job_ids).pluck(:id).to_set

        job_ids.filter_map do |job_id|
          next unless known_job_ids.include?(job_id)

          runs = scope.where(job_id: job_id).order(:duration).pluck(:duration, :status)
          durations = runs.map(&:first).compact.map(&:to_f)
          next if durations.empty?

          statuses = runs.map(&:second)
          row("RailsPulse::Job", job_id).merge(
            Metrics.duration(durations),
            count: runs.size,
            error_count: statuses.count { |s| s != "success" },
            success_count: statuses.count { |s| s == "success" }
          )
        end
      end

      # Per-group counts plus an all-groups row (id 0), so the dashboard can
      # chart total exception volume without loading one series per group.
      def exception_rows
        counts = ExceptionOccurrence.where(occurred_at: @time_range).group(:exception_group_id).count
        return [] if counts.empty?

        rows = counts.map { |group_id, occurrences| row("RailsPulse::ExceptionGroup", group_id).merge(count: occurrences) }
        rows << row("RailsPulse::ExceptionGroup", 0).merge(count: counts.values.sum)
      end

      private

      def row(summarizable_type, summarizable_id)
        { summarizable_type: summarizable_type, summarizable_id: summarizable_id }
      end

      def summarizable_ids(scope, column)
        scope.where.not(column => nil).distinct.pluck(column)
      end
    end
  end
end
