module RailsPulse
  module Operations
    # Maps the metric names the Operations API accepts onto the summary columns
    # that back them, and knows how to aggregate each one across several summary
    # rows.
    #
    # Duration metrics are traffic-weighted: a day with 10,000 requests should
    # move a baseline further than a day with 12. Averaging the stored
    # percentiles unweighted would let a quiet Sunday count as much as a busy
    # Monday and make every baseline noisy.
    module Metric
      DURATION_COLUMNS = {
        p50: "p50_duration",
        p95: "p95_duration",
        p99: "p99_duration",
        avg: "avg_duration"
      }.freeze

      SUPPORTED = (DURATION_COLUMNS.keys + [ :error_rate ]).freeze

      # Higher is worse for every metric currently supported, but stating it
      # explicitly keeps the comparison code from assuming it forever.
      def self.higher_is_worse?(_metric)
        true
      end

      def self.validate!(metric)
        return metric.to_sym if SUPPORTED.include?(metric.to_sym)

        raise ArgumentError, "unsupported metric #{metric.inspect} — expected one of #{SUPPORTED.join(', ')}"
      end

      def self.unit(metric)
        metric.to_sym == :error_rate ? "%" : "ms"
      end

      # SQL that reduces a set of summary rows to a single value for this metric.
      # NULLIF guards the zero-count case rather than letting the database raise
      # or return a division artifact.
      def self.aggregate_sql(metric)
        if metric.to_sym == :error_rate
          "SUM(rails_pulse_summaries.error_count) * 100.0 / " \
            "NULLIF(SUM(rails_pulse_summaries.count), 0)"
        else
          column = DURATION_COLUMNS.fetch(metric.to_sym)
          "SUM(rails_pulse_summaries.#{column} * rails_pulse_summaries.count) / " \
            "NULLIF(SUM(rails_pulse_summaries.count), 0)"
        end
      end

      # Reduces an already-loaded set of [value, count] pairs the same way
      # aggregate_sql would. Used by change-point detection, which needs the
      # per-period series in memory anyway and should not round-trip per split.
      def self.combine(pairs)
        total_count = pairs.sum { |(_value, count)| count.to_i }
        return nil if total_count.zero?

        weighted = pairs.sum { |(value, count)| value.to_f * count.to_i }
        weighted / total_count
      end
    end
  end
end
