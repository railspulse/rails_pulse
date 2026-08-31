module RailsPulse
  module Operations
    # Measures a subject's recent behaviour against its own history.
    #
    # This is the entry point for "what changed?", the question the dashboard's
    # threshold rules cannot answer. It reads only from summaries, which cleanup
    # retains at day granularity indefinitely, so a comparison stays available
    # long after the raw requests behind it have aged out.
    class Compare
      # @param subject [Route, Query, Job, :requests]
      # @param metric [Symbol] :p50, :p95, :p99, :avg or :error_rate
      # @param as_of [Time] treat this as "now"; the current window ends here
      # @return [Comparison] always returned — ask it whether it is comparable
      def self.call(subject, metric: :p95, as_of: Time.current)
        new(subject, metric: metric, as_of: as_of).call
      end

      # Compares every subject of a kind in one pass, for callers that need to
      # rank or filter across an application rather than inspect one route.
      #
      # @param scope [ActiveRecord::Relation, Class] Route, Query or Job
      # @return [Array<Comparison>] only comparisons with usable data on both sides
      def self.scan(scope, metric: :p95, as_of: Time.current)
        scope.find_each.filter_map do |record|
          comparison = call(record, metric: metric, as_of: as_of)
          comparison if comparison.sufficient_data?
        end
      end

      def initialize(subject, metric: :p95, as_of: Time.current)
        @subject = Subject.wrap(subject)
        @metric  = Metric.validate!(metric)
        @as_of   = as_of
      end

      def call
        current  = Series.load(subject, metric: metric, range: current_range,  period_type: period_type)
        baseline = Series.load(subject, metric: metric, range: baseline_range, period_type: period_type)

        Comparison.new(
          subject:          subject,
          metric:           metric,
          period_type:      period_type,
          baseline_value:   baseline.value,
          baseline_count:   baseline.total_count,
          baseline_periods: baseline.size,
          current_value:    current.value,
          current_count:    current.total_count
        )
      end

      private

      attr_reader :subject, :metric, :as_of

      def period_type
        "day"
      end

      def comparison_window
        RailsPulse.configuration.comparison_window
      end

      def baseline_window
        RailsPulse.configuration.baseline_window
      end

      # Windows are aligned to period boundaries rather than measured back from
      # the wall clock. Day summaries are written by SummaryJob at midnight for
      # the day that just ended, so an unaligned "now minus 24 hours" window
      # straddles two day-periods and matches neither — at noon it would contain
      # no day summary at all. Aligning means the current window is always the
      # most recent *complete* day.
      def current_end
        RailsPulse::Summary.normalize_period_start(period_type, as_of)
      end

      # The recent slice under test: the last complete period(s).
      def current_range
        (current_end - comparison_window)...current_end
      end

      # History, ending where the current window begins. The two must not
      # overlap: including the period under test in its own baseline damps
      # exactly the change the comparison exists to detect.
      def baseline_range
        baseline_end = current_end - comparison_window
        (baseline_end - baseline_window)...baseline_end
      end
    end
  end
end
