module RailsPulse
  module Dashboard
    class HealthSummary
      include Concerns::ThresholdConstants
      include Concerns::TimeRangeHelper

      def initialize(disabled_tags: [], show_non_tagged: true, period: 7)
        @disabled_tags   = disabled_tags
        @show_non_tagged = show_non_tagged
        @period          = period
        @route_thresholds = RailsPulse.configuration.route_thresholds
        @query_thresholds = RailsPulse.configuration.query_thresholds
        @job_thresholds   = RailsPulse.configuration.job_thresholds
      end

      def to_health_data
        {
          routes:  route_counts,
          queries: query_counts,
          jobs:    job_counts
        }
      end

      private

      def route_counts
        start, finish = period_range

        data = RailsPulse::Summary
          .with_tag_filters(@disabled_tags, @show_non_tagged)
          .where(summarizable_type: "RailsPulse::Route", period_start: start..finish)
          .group("summarizable_id")
          .select(
            "summarizable_id",
            "SUM(p95_duration * count) / NULLIF(SUM(count), 0) as p95_duration",
            "SUM(count) as total_count",
            "SUM(error_count) as total_errors"
          )

        healthy = slow = critical = 0
        data.each do |r|
          p95        = r.p95_duration.to_f
          total      = r.total_count.to_i
          errors     = r.total_errors.to_i
          error_rate = total > 0 ? (errors * 100.0 / total) : 0.0

          if p95 >= @route_thresholds[:critical] || error_rate >= CRITICAL_ERROR_RATE
            critical += 1
          elsif p95 >= @route_thresholds[:slow] || error_rate >= WARNING_ERROR_RATE
            slow += 1
          else
            healthy += 1
          end
        end

        { healthy: healthy, slow: slow, critical: critical }
      end

      def query_counts
        start, finish = period_range

        data = RailsPulse::Summary
          .with_tag_filters(@disabled_tags, @show_non_tagged)
          .where(summarizable_type: "RailsPulse::Query", period_start: start..finish)
          .group("summarizable_id")
          .select(
            "summarizable_id",
            "SUM(p95_duration * count) / NULLIF(SUM(count), 0) as p95_duration"
          )

        healthy = slow = critical = 0
        data.each do |r|
          p95 = r.p95_duration.to_f

          if p95 >= @query_thresholds[:critical]
            critical += 1
          elsif p95 >= @query_thresholds[:slow]
            slow += 1
          else
            healthy += 1
          end
        end

        { healthy: healthy, slow: slow, critical: critical }
      end

      def job_counts
        return nil unless RailsPulse.configuration.track_jobs

        healthy = slow = critical = 0
        RailsPulse::Job.where("runs_count > 0").each do |job|
          failure_rate = job.failure_rate
          p95          = job.p95_duration.to_f

          if failure_rate >= CRITICAL_JOB_FAILURE_RATE || p95 >= @job_thresholds[:critical]
            critical += 1
          elsif failure_rate >= WARNING_JOB_FAILURE_RATE || p95 >= @job_thresholds[:slow]
            slow += 1
          else
            healthy += 1
          end
        end

        { healthy: healthy, slow: slow, critical: critical }
      end
    end
  end
end
