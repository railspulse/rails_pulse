module RailsPulse
  module Operations
    # The result of measuring a recent window against a historical baseline.
    #
    # This is a value object on purpose. It is the shape callers outside this
    # namespace — dashboards today, findings and Pro tooling later — are expected
    # to depend on, so it carries every number needed to explain the verdict
    # rather than just the verdict.
    class Comparison
      attr_reader :subject, :metric, :baseline_value, :baseline_count, :baseline_periods,
                  :current_value, :current_count, :period_type

      def initialize(subject:, metric:, period_type:,
                     baseline_value:, baseline_count:, baseline_periods:,
                     current_value:, current_count:)
        @subject          = subject
        @metric           = metric
        @period_type      = period_type
        @baseline_value   = baseline_value
        @baseline_count   = baseline_count
        @baseline_periods = baseline_periods
        @current_value    = current_value
        @current_count    = current_count
      end

      # True when both sides produced a value. A comparison can be well-formed
      # and still not be a regression; this only says the arithmetic is possible.
      def comparable?
        !baseline_value.nil? && !current_value.nil? && baseline_value.to_f > 0
      end

      def delta
        return nil unless comparable?

        current_value - baseline_value
      end

      def ratio
        return nil unless comparable?

        current_value / baseline_value
      end

      def percent_change
        return nil unless comparable?

        (ratio - 1) * 100
      end

      def direction
        return :unknown unless comparable?
        return :flat if delta.abs < Float::EPSILON

        delta.positive? ? :up : :down
      end

      def unit
        Metric.unit(metric)
      end

      # Enough traffic and enough history for the comparison to mean anything.
      # Checked separately from `regression?` so a caller can tell "nothing
      # happened" apart from "not enough data to say".
      def sufficient_data?
        return false unless comparable?

        thresholds = RailsPulse.configuration.regression_thresholds

        baseline_periods >= thresholds[:min_baseline_periods] &&
          baseline_count  >= thresholds[:min_samples] &&
          current_count   >= thresholds[:min_samples]
      end

      # A deterministic regression: the metric grew by at least the configured
      # multiple AND by at least the absolute floor for its unit. Both gates
      # matter — the ratio alone flags trivial millisecond noise on fast
      # endpoints, and the floor alone flags slow endpoints that never changed.
      def regression?
        return false unless sufficient_data?
        return false unless Metric.higher_is_worse?(metric)

        thresholds = RailsPulse.configuration.regression_thresholds
        floor      = metric == :error_rate ? thresholds[:min_delta_rate] : thresholds[:min_delta_ms]

        ratio >= thresholds[:ratio] && delta >= floor
      end

      # One line a human can check the maths against. Findings and API output
      # both render from this rather than each inventing their own phrasing.
      def summary
        return "not enough data to compare" unless comparable?

        "#{metric.to_s.upcase} #{format_value(baseline_value)} → #{format_value(current_value)} " \
          "(#{percent_change.positive? ? '+' : ''}#{percent_change.round(1)}%)"
      end

      def to_h
        {
          subject_type:     subject.type,
          subject_id:       subject.id,
          subject_label:    subject.label,
          metric:           metric,
          unit:             unit,
          period_type:      period_type,
          baseline_value:   baseline_value,
          baseline_count:   baseline_count,
          baseline_periods: baseline_periods,
          current_value:    current_value,
          current_count:    current_count,
          delta:            delta,
          ratio:            ratio,
          percent_change:   percent_change,
          direction:        direction,
          sufficient_data:  sufficient_data?,
          regression:       regression?
        }
      end

      private

      def format_value(value)
        metric == :error_rate ? "#{value.round(2)}%" : "#{value.round(0).to_i}ms"
      end
    end
  end
end
