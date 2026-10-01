module RailsPulse
  class SummaryService
    # Summary rows for a day, week or month, rolled up from the summaries of
    # its child periods (hours for a day, days for a week or month) without
    # reading raw rows.
    #
    # Counts, totals, averages, min, max, status counts and the standard
    # deviation combine exactly. P50/P95/P99 are the count-weighted average of
    # the children's, the same weighting Tables::Base applies when a
    # dashboard range spans several periods.
    #
    # Rows carry the summarizable and its metrics; SummaryService adds the
    # period columns.
    class FromChildPeriods
      COLUMNS = %i[
        summarizable_type summarizable_id count avg_duration min_duration max_duration
        total_duration p50_duration p95_duration p99_duration stddev_duration
        error_count success_count status_2xx status_3xx status_4xx status_5xx
      ].freeze
      STATUS_COLUMNS = %i[error_count success_count status_2xx status_3xx status_4xx status_5xx].freeze

      # `child_starts` are the boundaries the children must start on. Rows in
      # the range that start elsewhere were written under a different
      # aggregation time zone; they overlap these and would be counted twice.
      def initialize(child_period_type, child_starts, time_range)
        @child_period_type = child_period_type
        @child_starts = child_starts.to_set(&:to_i)
        @time_range = time_range
      end

      # Always exactly one row, even for an empty period (see SummaryService).
      def request_rows
        children = children_by_summarizable.fetch([ "RailsPulse::Request", 0 ], [])

        [ row("RailsPulse::Request", 0).merge(duration_metrics(children), status_metrics(children)) ]
      end

      def route_rows
        children_of("RailsPulse::Route").map do |route_id, children|
          row("RailsPulse::Route", route_id).merge(duration_metrics(children), status_metrics(children))
        end
      end

      def query_rows
        children_of("RailsPulse::Query").map do |query_id, children|
          row("RailsPulse::Query", query_id).merge(duration_metrics(children))
        end
      end

      def job_rows
        children_by_job = children_of("RailsPulse::Job")
        return [] if children_by_job.empty?

        # A job whose row has gone (count-based cleanup) has nothing to
        # summarize against.
        known_job_ids = Job.where(id: children_by_job.keys).pluck(:id).to_set

        children_by_job.filter_map do |job_id, children|
          next unless known_job_ids.include?(job_id)

          row("RailsPulse::Job", job_id).merge(
            duration_metrics(children),
            status_metrics(children).slice(:error_count, :success_count)
          )
        end
      end

      # The children already carry the all-groups row (id 0), which sums like
      # any other group.
      def exception_rows
        children_of("RailsPulse::ExceptionGroup").map do |group_id, children|
          row("RailsPulse::ExceptionGroup", group_id).merge(count: children.sum { |child| child[:count].to_i })
        end
      end

      private

      def row(summarizable_type, summarizable_id)
        { summarizable_type: summarizable_type, summarizable_id: summarizable_id }
      end

      def children_by_summarizable
        @children_by_summarizable ||= Summary
          .where(period_type: @child_period_type, period_start: @time_range)
          .pluck(:period_start, *COLUMNS)
          .select { |period_start, *| @child_starts.include?(period_start.to_i) }
          .map { |_, *values| COLUMNS.zip(values).to_h }
          .group_by { |child| [ child[:summarizable_type], child[:summarizable_id] ] }
      end

      # { summarizable_id => [child rows] } for one summarizable type.
      def children_of(summarizable_type)
        children_by_summarizable.each_with_object({}) do |((type, id), children), by_id|
          by_id[id] = children if type == summarizable_type
        end
      end

      def duration_metrics(children)
        children = children.select { |child| child[:count].to_i.positive? }
        count = children.sum { |child| child[:count] }
        return Metrics.duration([]) if count.zero?

        total = children.sum { |child| child[:total_duration].to_f }
        weighted = ->(column) { Statistics.weighted_mean(children.map { |child| [ child[column], child[:count] ] }) }

        {
          count: count,
          avg_duration: total / count,
          min_duration: children.filter_map { |child| child[:min_duration] }.min,
          max_duration: children.filter_map { |child| child[:max_duration] }.max,
          total_duration: total,
          p50_duration: weighted.call(:p50_duration),
          p95_duration: weighted.call(:p95_duration),
          p99_duration: weighted.call(:p99_duration),
          stddev_duration: Statistics.pooled_stddev(children.map { |child| [ child[:count], child[:avg_duration], child[:stddev_duration] ] })
        }
      end

      def status_metrics(children)
        STATUS_COLUMNS.index_with { |column| children.sum { |child| child[column].to_i } }
      end
    end
  end
end
