module RailsPulse
  module Operations
    # Loads a subject's metric as an ordered time series of summary periods.
    #
    # Every operation in this namespace reads through here, so there is exactly
    # one place that knows how summaries are queried. The row counts involved are
    # small by construction — 30 day-periods for a month of baseline, 48
    # hour-periods for the retained hourly window — so the reduction happens in
    # Ruby rather than in SQL. That keeps one code path across SQLite, PostgreSQL
    # and MySQL instead of three dialects of weighted average.
    class Series
      Point = Struct.new(:period_start, :period_end, :value, :count, keyword_init: true)

      attr_reader :subject, :metric, :period_type, :points

      def self.load(subject, metric:, range:, period_type: "day")
        subject = Subject.wrap(subject)
        metric  = Metric.validate!(metric)

        rows = subject.summaries
          .where(period_type: period_type)
          .where(period_start: range)
          .order(:period_start)
          .pluck(:period_start, :period_end, :count, :p50_duration, :p95_duration, :p99_duration, :avg_duration, :error_count)

        points = rows.filter_map do |period_start, period_end, count, p50, p95, p99, avg, error_count|
          value = extract(metric, p50: p50, p95: p95, p99: p99, avg: avg, count: count, error_count: error_count)
          next if value.nil?

          Point.new(period_start: period_start, period_end: period_end, value: value.to_f, count: count.to_i)
        end

        new(subject: subject, metric: metric, period_type: period_type, points: points)
      end

      def self.extract(metric, p50:, p95:, p99:, avg:, count:, error_count:)
        case metric
        when :p50 then p50
        when :p95 then p95
        when :p99 then p99
        when :avg then avg
        when :error_rate
          count.to_i.zero? ? nil : (error_count.to_i * 100.0 / count.to_i)
        end
      end
      private_class_method :extract

      def initialize(subject:, metric:, period_type:, points:)
        @subject     = subject
        @metric      = metric
        @period_type = period_type
        @points      = points
      end

      def empty?
        points.empty?
      end

      def size
        points.size
      end

      # Total observations behind the series — requests, executions or runs,
      # depending on the subject. Used to decide whether a comparison has enough
      # traffic to be worth reporting.
      def total_count
        @total_count ||= points.sum(&:count)
      end

      # The traffic-weighted value across every period in the series.
      def value
        @value ||= Metric.combine(points.map { |point| [ point.value, point.count ] })
      end

      def first_period_start
        points.first&.period_start
      end

      def last_period_start
        points.last&.period_start
      end
    end
  end
end
