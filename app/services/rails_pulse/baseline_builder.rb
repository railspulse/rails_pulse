module RailsPulse
  # Rebuilds the stored baseline of every route, query and job: what normal
  # looks like for that one subject, as its P50, P90 and P95 across
  # `config.baseline_window` of complete day summaries.
  #
  # The baseline lives in columns on the subject's own row rather than being
  # computed on read, so a table can sort and filter on "slow against its own
  # normal" without aggregating a month of summaries per page load, and the
  # writer can load every subject's threshold in one query.
  #
  # Percentiles are traffic-weighted across the days, the weighting
  # Operations::Metric and SummaryService::FromChildPeriods apply: a day with
  # 10,000 requests moves the baseline further than a day with 12. A day whose
  # summary has no value for a percentile adds nothing to that percentile's
  # weight, so days summarized before a percentile was recorded do not drag
  # it towards zero.
  #
  # Every subject row is rewritten on each run. One with no day summaries in
  # the window gets NULL percentiles and zero counts, so a baseline never
  # outlives the history it was built from, and `baseline_computed_at` is the
  # time of the last rebuild for all of them. `baseline_sample_count` and
  # `baseline_periods` let a reader decide whether a baseline rests on enough
  # history to trust.
  #
  # The work is one UPDATE per batch with correlated subqueries against the
  # summaries index, so no summary rows are loaded into Ruby and no statement
  # holds a table's rows for long. `update_all` leaves `updated_at` alone.
  class BaselineBuilder
    SUBJECTS = [ RailsPulse::Route, RailsPulse::Query, RailsPulse::Job ].freeze
    PERCENTILES = {
      baseline_p50_duration: "p50_duration",
      baseline_p90_duration: "p90_duration",
      baseline_p95_duration: "p95_duration"
    }.freeze
    BATCH_SIZE = 1_000

    # The baseline columns, rescued — false for an upgrader who has not
    # migrated yet.
    def self.columns_available?
      SUBJECTS.all? { |subject| subject.connection.column_exists?(subject.table_name, :baseline_computed_at) }
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def initialize(as_of: Time.current)
      @as_of = as_of
    end

    # Returns the number of subject rows rewritten.
    def perform
      SUBJECTS.sum do |subject|
        assignments = [ assignments_sql(subject), bindings(subject) ]
        subject.in_batches(of: BATCH_SIZE).sum { |batch| batch.update_all(assignments) }
      end
    end

    # The complete days the baseline covers, ending with yesterday: today's
    # day summary is not written until midnight.
    def window
      window_end = RailsPulse::Summary.normalize_period_start("day", @as_of)
      (window_end - RailsPulse.configuration.baseline_window)...window_end
    end

    private

    def assignments_sql(subject)
      days = days_sql(subject)

      percentiles = PERCENTILES.map do |baseline_column, summary_column|
        weighted = "SUM(s.#{summary_column} * s.count)"
        weight = "SUM(CASE WHEN s.#{summary_column} IS NOT NULL THEN s.count ELSE 0 END)"
        "#{baseline_column} = (SELECT #{weighted} / NULLIF(#{weight}, 0) #{days})"
      end

      [
        *percentiles,
        "baseline_sample_count = COALESCE((SELECT SUM(s.count) #{days}), 0)",
        "baseline_periods = (SELECT COUNT(*) #{days})",
        "baseline_computed_at = :computed_at"
      ].join(", ")
    end

    # Days with no traffic are skipped: they would count as periods of
    # history while saying nothing about how long the subject takes.
    def days_sql(subject)
      "FROM rails_pulse_summaries s " \
        "WHERE s.summarizable_type = :summarizable_type " \
        "AND s.summarizable_id = #{subject.quoted_table_name}.#{subject.connection.quote_column_name(subject.primary_key)} " \
        "AND s.period_type = 'day' " \
        "AND s.period_start >= :window_start AND s.period_start < :window_end " \
        "AND s.count > 0"
    end

    def bindings(subject)
      {
        summarizable_type: subject.name,
        window_start: window.begin,
        window_end: window.end,
        computed_at: @as_of
      }
    end
  end
end
