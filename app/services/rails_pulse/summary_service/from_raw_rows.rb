module RailsPulse
  class SummaryService
    # Summary rows for an hour, computed from raw requests, operations, job
    # runs and exception occurrences.
    #
    # Each kind is read with one query, sorted by summarizable and then
    # duration so every summarizable's durations arrive as one consecutive,
    # already-sorted run; the overall request row and the per-route rows
    # share a single read. Memory is bounded by one hour's rows, and the
    # hour costs one query per kind however many routes, queries or jobs it
    # saw. Percentiles are exact.
    #
    # Rows carry the summarizable and its metrics; SummaryService adds the
    # period columns.
    class FromRawRows
      def initialize(time_range)
        @time_range = time_range
      end

      # Always exactly one row, even for an empty hour (see SummaryService).
      def request_rows
        durations = request_data.map { |_, duration, _| duration }.compact.sort
        statuses = request_data.map { |_, _, status| status }

        [ row("RailsPulse::Request", 0).merge(Metrics.duration(durations), Metrics.status(statuses)) ]
      end

      def route_rows
        request_data.slice_when { |previous, current| previous.first != current.first }.map do |rows|
          durations = rows.map { |_, duration, _| duration }
          statuses = rows.map { |_, _, status| status }

          row("RailsPulse::Route", rows.first.first).merge(
            Metrics.duration(durations),
            Metrics.status(statuses),
            count: rows.size
          )
        end
      end

      def query_rows
        rows_by_summarizable(Operation.where(occurred_at: @time_range), :query_id).filter_map do |query_id, rows|
          durations = rows.map(&:first).compact
          next if durations.empty?

          row("RailsPulse::Query", query_id).merge(Metrics.duration(durations))
        end
      end

      def job_rows
        scope = JobRun.where(occurred_at: @time_range).where(status: JobRun::FINAL_STATUSES)
        runs_by_job = rows_by_summarizable(scope, :job_id, :status)
        return [] if runs_by_job.empty?

        # A run whose job row has gone (count-based cleanup) has nothing to
        # summarize against.
        known_job_ids = Job.where(id: runs_by_job.map(&:first)).pluck(:id).to_set

        runs_by_job.filter_map do |job_id, runs|
          next unless known_job_ids.include?(job_id)

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

      # One read serves the overall request row and every route's. route_id
      # and duration are NOT NULL on requests, so ordering by (route_id,
      # duration) hands each route its durations already sorted.
      def request_data
        @request_data ||= Request
          .where(occurred_at: @time_range)
          .order(:route_id, :duration)
          .pluck(:route_id, :duration, :status)
      end

      # [[summarizable_id, [[duration, *extra_columns], ...]], ...], with
      # each summarizable's rows in ascending duration order (NULL durations
      # land at one end or the other depending on the database; callers
      # compact them).
      def rows_by_summarizable(scope, column, *extra_columns)
        scope
          .where.not(column => nil)
          .order(column, :duration)
          .pluck(column, :duration, *extra_columns)
          .slice_when { |previous, current| previous.first != current.first }
          .map { |rows| [ rows.first.first, rows.map { |row| row.drop(1) } ] }
      end
    end
  end
end
