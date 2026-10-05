module RailsPulse
  # Whether a deployment made the application slower or more error-prone,
  # answered from the hourly overall request summaries either side of it.
  #
  # Every hour the deploy ran in is skipped: during a rolling deploy those
  # hours hold traffic from both versions. "Before" is the hour ending at
  # the start of the hour the deploy started in, "after" the hour following
  # the hour it finished in (the start hour when no finish was recorded), so
  # a deploy running 14:28-15:40 compares 13:00-14:00 with 16:00-17:00, and
  # its answer is available once SummaryJob has summarized 16:00.
  #
  # Computed on request and never stored. A metric degraded when it is more
  # than its multiplier worse after the deploy and worse by at least the
  # regression_thresholds absolute floor; either window holding fewer than
  # MINIMUM_REQUESTS requests makes the comparison insufficient_data.
  class DeploymentComparison
    METRICS = %i[avg_response_time p95_response_time error_rate].freeze

    MULTIPLIERS = {
      avg_response_time: 1.5,
      p95_response_time: 1.5,
      error_rate:        1.25
    }.freeze

    UNITS = {
      avg_response_time: "ms",
      p95_response_time: "ms",
      error_rate:        "%"
    }.freeze

    MINIMUM_REQUESTS = 10

    # SummaryJob runs hourly, so the after-hour's row should exist within
    # this long of that hour ending; a row still missing after that will not
    # appear on its own, and the comparison is reported unavailable rather
    # than leaving a polling agent waiting on a job that is not running.
    SUMMARY_GRACE = 2.hours

    # One comparison per deployment, reading every hourly row they need in
    # a single query so a page of deployments costs one statement.
    #
    # @return [Hash{Integer => Hash}] keyed by deployment id
    def self.for(deployments)
      deployments = deployments.to_a
      return {} if deployments.empty?

      hours = deployments.flat_map { |deployment| windows(deployment).values }
      rows = RailsPulse::Summary.overall_requests
        .where(period_type: "hour", period_start: hours.uniq)
        .index_by(&:period_start)

      deployments.to_h do |deployment|
        [ deployment.id, new(deployment, rows: rows).call ]
      end
    end

    # The start of the hour before a deployment and the hour after it. The
    # after window follows the hour the deploy finished in, so a rolling
    # deploy that ran past the top of the hour does not leak mixed-version
    # traffic into the measurement.
    def self.windows(deployment)
      start_hour  = RailsPulse::Summary.normalize_period_start("hour", deployment.started_at.in_time_zone)
      finish_hour = if deployment.finished_at
        RailsPulse::Summary.normalize_period_start("hour", deployment.finished_at.in_time_zone)
      else
        start_hour
      end
      { before: start_hour - 1.hour, after: finish_hour + 1.hour }
    end

    def initialize(deployment, rows: nil, now: Time.current)
      @deployment = deployment
      @now = now
      @windows = self.class.windows(deployment)
      @rows = rows || RailsPulse::Summary.overall_requests
        .where(period_type: "hour", period_start: @windows.values)
        .index_by(&:period_start)
    end

    def call
      before = @rows[@windows[:before]]
      after = @rows[@windows[:after]]
      metrics = METRICS.map { |metric| compare(metric, before, after) }

      {
        outcome: outcome(metrics, after),
        before:  window(@windows[:before], before),
        after:   window(@windows[:after], after),
        metrics: metrics,
        note:    note(before, after)
      }.compact
    end

    private

    def compare(metric, before, after)
      result = { metric: metric, unit: UNITS[metric], multiplier: MULTIPLIERS[metric] }

      unless sufficient?(before) && sufficient?(after)
        return result.merge(outcome: "insufficient_data", before: nil, after: nil, ratio: nil)
      end

      before_value = value(metric, before)
      after_value = value(metric, after)

      result.merge(
        outcome: degraded?(metric, before_value, after_value) ? "degraded" : "clean",
        before:  before_value.round(2),
        after:   after_value.round(2),
        ratio:   before_value.zero? ? nil : (after_value / before_value).round(3)
      )
    end

    # Both gates matter, as in Operations::Comparison#regression?: the ratio
    # alone flags trivial noise (8ms to 13ms is 1.6x), and the floor alone
    # flags slow endpoints that barely moved. Errors where there were none is
    # degraded once past the floor, though it has no ratio.
    def degraded?(metric, before_value, after_value)
      return false unless after_value - before_value >= min_delta(metric)
      return true if before_value.zero?

      after_value / before_value > MULTIPLIERS[metric]
    end

    def min_delta(metric)
      thresholds = RailsPulse.configuration.regression_thresholds
      metric == :error_rate ? thresholds[:min_delta_rate].to_f : thresholds[:min_delta_ms].to_f
    end

    def value(metric, row)
      case metric
      when :avg_response_time then row.avg_duration.to_f
      when :p95_response_time then row.p95_duration.to_f
      when :error_rate        then row.error_count.to_f / row.count * 100
      end
    end

    def sufficient?(row)
      row.present? && row.count.to_i >= MINIMUM_REQUESTS
    end

    # A missing after-hour row is pending only while SummaryJob could still
    # write it; past SUMMARY_GRACE it is unavailable, a distinct value so an
    # agent polling for the comparison is not left waiting forever when the
    # job is not running (note says which).
    def outcome(metrics, after)
      if after.nil? && !pruned?(@windows[:after])
        return @now < @windows[:after] + 1.hour + SUMMARY_GRACE ? "pending" : "unavailable"
      end
      return "degraded" if metrics.any? { |m| m[:outcome] == "degraded" }
      return "insufficient_data" if metrics.any? { |m| m[:outcome] == "insufficient_data" }

      "clean"
    end

    def window(start, row)
      { from: start, to: start + 1.hour, requests: row&.count.to_i }
    end

    def note(before, after)
      if (after.nil? && pruned?(@windows[:after])) || (before.nil? && pruned?(@windows[:before]))
        "Hourly summaries this far back have been pruned (config.hourly_summary_retention keeps " \
          "#{(RailsPulse.configuration.hourly_summary_retention / 1.day).round(1)} days), so this deployment can no longer be compared."
      elsif after.nil? && @windows[:after] + 1.hour > @now
        "The hour after the deploy ends at #{(@windows[:after] + 1.hour).iso8601}; the comparison is available once SummaryJob has summarized it."
      elsif after.nil?
        "The hour after the deploy has not been summarized. Check that RailsPulse::SummaryJob is scheduled hourly."
      elsif !sufficient?(before) || !sufficient?(after)
        "Fewer than #{MINIMUM_REQUESTS} requests in the hour before or after the deploy, too few to compare."
      end
    end

    def pruned?(hour_start)
      hour_start < RailsPulse.configuration.hourly_summary_retention.ago
    end
  end
end
