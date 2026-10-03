module RailsPulse
  # Whether a deployment made the application slower or more error-prone,
  # answered from the hourly overall request summaries either side of it.
  #
  # The hour the deploy started in is skipped: during a rolling deploy it
  # holds traffic from both versions. "Before" is the hour ending at the
  # start of that hour and "after" the hour that follows it, so a deploy at
  # 14:28 compares 13:00-14:00 with 15:00-16:00, and its answer is available
  # once SummaryJob has summarized 15:00.
  #
  # Computed on request and never stored. A metric degraded when it is more
  # than its multiplier worse after the deploy; either window holding fewer
  # than MINIMUM_REQUESTS requests makes the comparison insufficient_data.
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

    # The start of the hour before and the hour after a deployment.
    def self.windows(deployment)
      deploy_hour = RailsPulse::Summary.normalize_period_start("hour", deployment.started_at.in_time_zone)
      { before: deploy_hour - 1.hour, after: deploy_hour + 1.hour }
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

    # Errors where there were none is degraded, though it has no ratio.
    def degraded?(metric, before_value, after_value)
      return after_value.positive? if before_value.zero?

      after_value / before_value > MULTIPLIERS[metric]
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

    def outcome(metrics, after)
      return "pending" if after.nil? && !pruned?(@windows[:after])
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
