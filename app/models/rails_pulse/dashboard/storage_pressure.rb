module RailsPulse
  module Dashboard
    class StoragePressure
      STALE_WARNING_THRESHOLD  = 2.hours
      STALE_CRITICAL_THRESHOLD = 24.hours

      def initialize
        @config = RailsPulse.configuration
      end

      # Memoized: computing the items costs several aggregate queries (one a
      # raw-request count), and one dashboard render asks for them repeatedly.
      def pressure_items
        @pressure_items ||= summary_staleness_items + sub_hour_retention_items + writer_drop_items
      end

      # Dropped requests get their own Tracking badge, not this one
      def storage_counts
        items    = pressure_items.reject { |i| i[:type] == "TRACKING" }
        critical = items.any? { |i| i[:severity] == :critical } ? 1 : 0
        slow     = (critical.zero? && items.any? { |i| i[:severity] == :warning }) ? 1 : 0
        healthy  = (critical.zero? && slow.zero?) ? 1 : 0
        { healthy: healthy, slow: slow, critical: critical }
      end

      private

      # Signal A — Summary job staleness
      def summary_staleness_items
        latest_end = latest_hourly_request_summary_end

        if latest_end.nil?
          return [ stale_item(:critical, "Summary job has never run",
                              "never run", "Schedule it to run hourly to enable cleanup") ]
        end

        age = Time.current - latest_end

        if age >= STALE_CRITICAL_THRESHOLD
          hours = (age / 1.hour).round
          [ stale_item(:critical, "Summary job is #{hours}h behind",
                       "#{hours}h stale", "Last run: #{latest_end.strftime("%Y-%m-%d %H:%M")} (#{RailsPulse::TimeRange.aggregation_zone_label})") ]
        elsif age >= STALE_WARNING_THRESHOLD
          hours = (age / 1.hour).round
          [ stale_item(:warning, "Summary job is #{hours}h behind",
                       "#{hours}h stale", "Last run: #{latest_end.strftime("%Y-%m-%d %H:%M")} (#{RailsPulse::TimeRange.aggregation_zone_label})") ]
        else
          []
        end
      end

      # Signal B — Retention period shorter than 1-hour cleanup minimum
      def sub_hour_retention_items
        return [] unless @config.full_retention_period
        return [] unless @config.full_retention_period < 1.hour

        minutes = (@config.full_retention_period / 1.minute).round
        [ {
          type:          "STORAGE",
          name:          "Retention period misconfigured",
          reason:        "full_retention_period (#{minutes}m) is shorter than 1 hour — cleanup enforces a 1-hour minimum to allow summaries to run first",
          metric:        "#{minutes}m configured",
          metric_sub:    "1h minimum enforced",
          link:          "#",
          severity:      :warning,
          sort_score:    0.0,
          popover_title: "Retention period is shorter than the cleanup minimum",
          popover_body:  "<code>full_retention_period</code> is set to #{minutes} minutes, but CleanupService enforces a 1-hour minimum. " \
                         "This means records will be kept for at least 1 hour regardless of your configured value.<br><br>" \
                         "The minimum exists because the summary job needs to process a period before cleanup can safely delete records from it. " \
                         "If cleanup ran sooner, those requests would be permanently lost from dashboard charts.<br><br>" \
                         "<strong>How to fix:</strong> Update your Rails Pulse configuration to set <code>full_retention_period</code> " \
                         "to at least <code>1.hour</code>. For most applications, a value of <code>7.days</code> or <code>30.days</code> is recommended."
        } ]
      end

      # Signal C — the background writer is discarding requests
      def writer_drop_items
        return [] unless RailsPulse::Event.table_available?

        summary = RailsPulse::WriterHeartbeat.summary
        dropped = summary[:dropped].to_i
        return [] if dropped.zero?

        [ {
          type:          "TRACKING",
          name:          "Writer queue dropping requests",
          reason:        "#{dropped} #{"request".pluralize(dropped)} dropped in the last hour — charts are missing samples",
          metric:        "#{dropped} dropped",
          metric_sub:    "last hour, #{summary[:processes]} live #{"writer".pluralize(summary[:processes])}",
          link:          "#",
          severity:      :critical,
          sort_score:    dropped.to_f,
          popover_title: "The tracking queue is overflowing",
          popover_body:  "Each process queues tracked requests for one background writer. When the queue (#{summary[:queue_size]} requests, " \
                         "<code>config.async_queue_size</code>) is full the newest request is dropped rather than slowing the app, so the " \
                         "dashboard undercounts traffic while this lasts.<br><br>" \
                         "<strong>How to fix:</strong> raise <code>config.async_queue_size</code> in the Rails Pulse initializer, or find out " \
                         "why the writer cannot keep up: database latency, a saturated connection pool, or a burst far above normal traffic. " \
                         "<code>rails rails_pulse:status</code> reports the same numbers from the shell."
        } ]
      rescue ActiveRecord::ActiveRecordError
        []
      end

      def stale_item(severity, reason, metric, metric_sub)
        {
          type:          "STORAGE",
          name:          "Summary job",
          reason:        reason,
          metric:        metric,
          metric_sub:    metric_sub,
          link:          "#",
          severity:      severity,
          sort_score:    severity == :critical ? Float::INFINITY : 1.0,
          popover_title: "Summary job is not running",
          popover_body:  "Rails Pulse summarises raw request data into hourly aggregates for the dashboard's charts. " \
                         "Count-based cleanup only trims records from periods that have been summarised, so until the job catches up tables can grow past <code>max_table_records</code>.<br><br>" \
                         "<strong>How to fix:</strong> Schedule <code>RailsPulse::SummaryJob</code> to run every hour in your job scheduler " \
                         "(Sidekiq-Cron, GoodJob, Solid Queue, etc.). Once it has run, cleanup will resume automatically on its next execution.<br><br>" \
                         "To backfill any historical gaps, run: <code>rails rails_pulse:backfill_summaries</code>"
        }
      end

      def latest_hourly_request_summary_end
        RailsPulse::Summary
          .where(summarizable_type: "RailsPulse::Request", summarizable_id: 0, period_type: "hour")
          .maximum(:period_end)
      end
    end
  end
end
