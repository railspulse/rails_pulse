module RailsPulse
  module Operations
    # Estimates when a metric changed, by finding the split in a time series that
    # best separates it into a "before" and an "after".
    #
    # The method is a single-pass step search: try every split with enough
    # periods on each side, and keep the one that maximises the gap between the
    # traffic-weighted mean before it and after it. That is deliberately simpler
    # than a statistical change-point model. It is explainable — the UI can show
    # a user the two means it compared — and it does not need a distributional
    # assumption to defend.
    #
    # Precision is bounded by what summaries still exist. Hourly summaries are
    # pruned at `hourly_summary_retention` (2 days by default), so a change point
    # can only be pinned to the hour inside that window. Beyond it the answer is
    # a day, and `granularity` says which the caller got — never silently one
    # pretending to be the other.
    class ChangePoint
      MIN_PERIODS_PER_SIDE = 2

      Result = Struct.new(
        :at, :granularity, :before_value, :after_value, :before_count, :after_count,
        keyword_init: true
      ) do
        def ratio
          return nil if before_value.nil? || before_value.zero?

          after_value / before_value
        end

        def delta
          return nil if before_value.nil? || after_value.nil?

          after_value - before_value
        end

        # True when the estimate sits inside the retained hourly window, so `at`
        # is accurate to the hour rather than the day.
        def hourly?
          granularity == "hour"
        end

        def to_h
          {
            at:           at,
            granularity:  granularity,
            before_value: before_value,
            after_value:  after_value,
            before_count: before_count,
            after_count:  after_count,
            ratio:        ratio,
            delta:        delta
          }
        end
      end

      # @param subject [Route, Query, Job, :requests]
      # @param metric [Symbol] :p50, :p95, :p99, :avg or :error_rate
      # @param range [Range<Time>] the window to search within
      # @return [Result, nil] nil when there is not enough of a series to split
      def self.call(subject, metric: :p95, range: nil)
        range ||= default_range
        new(subject, metric: metric, range: range).call
      end

      def self.default_range
        (RailsPulse.configuration.baseline_window.ago..Time.current)
      end

      def initialize(subject, metric:, range:)
        @subject = Subject.wrap(subject)
        @metric  = Metric.validate!(metric)
        @range   = range
      end

      def call
        series = best_available_series
        return nil if series.nil? || series.size < MIN_PERIODS_PER_SIDE * 2

        split = best_split(series)
        return nil if split.nil?

        before = series.points[0...split]
        after  = series.points[split..]

        Result.new(
          at:           after.first.period_start,
          granularity:  series.period_type,
          before_value: Metric.combine(before.map { |p| [ p.value, p.count ] }, metric),
          after_value:  Metric.combine(after.map { |p| [ p.value, p.count ] }, metric),
          before_count: before.sum(&:count),
          after_count:  after.sum(&:count)
        )
      end

      private

      attr_reader :subject, :metric, :range

      # Prefer hourly precision, but only where hourly summaries are actually
      # retained. Asking for hours outside that window returns a truncated series
      # that would place the change point at the edge of retention rather than
      # where it happened — worse than honestly answering in days.
      def best_available_series
        hourly = hourly_series
        return hourly if hourly && hourly.size >= MIN_PERIODS_PER_SIDE * 2

        daily = Series.load(subject, metric: metric, range: range, period_type: "day")
        daily.empty? ? hourly : daily
      end

      def hourly_series
        retention_start = RailsPulse.configuration.hourly_summary_retention.ago
        return nil if range.end && range.end < retention_start

        hourly_range = ([ range.begin, retention_start ].compact.max)..range.end
        series = Series.load(subject, metric: metric, range: hourly_range, period_type: "hour")
        series.empty? ? nil : series
      end

      # Returns the index the "after" side starts at, or nil if no split has
      # enough periods on both sides.
      def best_split(series)
        points = series.points
        best_index = nil
        best_gap   = 0.0

        (MIN_PERIODS_PER_SIDE..(points.size - MIN_PERIODS_PER_SIDE)).each do |index|
          before = Metric.combine(points[0...index].map { |p| [ p.value, p.count ] }, series.metric)
          after  = Metric.combine(points[index..].map  { |p| [ p.value, p.count ] }, series.metric)
          next if before.nil? || after.nil?

          gap = (after - before).abs
          if gap > best_gap
            best_gap   = gap
            best_index = index
          end
        end

        best_index
      end
    end
  end
end
