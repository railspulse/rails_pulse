module RailsPulse
  module Dashboard
    class NeedsAttention
      include Concerns::AttentionClassification
      include Concerns::TimeRangeHelper

      def initialize(disabled_tags: [], show_non_tagged: true, period: 7, window: nil, storage_pressure: nil)
        @disabled_tags    = disabled_tags
        @show_non_tagged  = show_non_tagged
        @period           = period
        @window           = window
        @storage_pressure = storage_pressure
        @route_thresholds = RailsPulse.configuration.route_thresholds
        @query_thresholds = RailsPulse.configuration.query_thresholds
        @job_thresholds   = RailsPulse.configuration.job_thresholds
        @exception_thresholds = RailsPulse.configuration.exception_thresholds
      end

      MAX_ITEMS = 10

      def to_attention_data
        items    = route_items + query_items + job_items + exception_items
        critical = items.select { |i| i[:severity] == :critical }.sort_by { |i| -i[:sort_score] }
        warning  = items.select { |i| i[:severity] == :warning  }.sort_by { |i| -i[:sort_score] }

        capped = (critical + warning).first(MAX_ITEMS)

        # Storage pressure items are infrastructure signals — always shown,
        # never subject to the 10-item app-level cap, always prepended.
        storage        = storage_pressure_items
        storage_crit   = storage.select { |i| i[:severity] == :critical }
        storage_warn   = storage.select { |i| i[:severity] == :warning }

        {
          critical: storage_crit + capped.select { |i| i[:severity] == :critical },
          warning:  storage_warn + capped.select { |i| i[:severity] == :warning },
          total:    capped.size + storage.size
        }
      end

      private

      def storage_pressure_items
        (@storage_pressure || StoragePressure.new).pressure_items
      end

      # The dashboard window is user-selected, so the error-rate reason names
      # the window's real length rather than assuming a week.
      def span_phrase
        start, finish = period_range
        hours = ((finish - start) / 1.hour).round
        return "in the last #{hours} hour#{"s" unless hours == 1}" if hours <= 25

        days = (hours / 24.0).round
        "in the last #{days} day#{"s" unless days == 1}"
      end

      def url_helpers
        RailsPulse::Engine.routes.url_helpers
      end

      def route_items
        start, finish = period_range

        route_data = RailsPulse::Summary
          .with_tag_filters(@disabled_tags, @show_non_tagged)
          .joins("INNER JOIN rails_pulse_routes ON rails_pulse_routes.id = rails_pulse_summaries.summarizable_id")
          .where(summarizable_type: "RailsPulse::Route", period_start: start..finish)
          .group("rails_pulse_summaries.summarizable_id, rails_pulse_routes.path")
          .select(
            "rails_pulse_summaries.summarizable_id as route_id",
            "rails_pulse_routes.path",
            "SUM(rails_pulse_summaries.p95_duration * rails_pulse_summaries.count) / NULLIF(SUM(rails_pulse_summaries.count), 0) as p95_duration",
            "SUM(rails_pulse_summaries.count) as total_count",
            "SUM(rails_pulse_summaries.error_count) as total_errors"
          )

        items = []
        route_data.each do |record|
          p95        = record.p95_duration.to_f
          total      = record.total_count.to_i
          errors     = record.total_errors.to_i
          error_rate = total > 0 ? (errors * 100.0 / total).round(1) : 0.0

          severity, reason, metric, metric_sub, sort_score = classify_route(p95, total, errors, error_rate, span_phrase)
          next unless severity

          items << {
            type:       "ROUTE",
            name:       record.path,
            reason:     reason,
            metric:     metric,
            metric_sub: metric_sub,
            link:       url_helpers.route_path(record.route_id),
            severity:   severity,
            sort_score: sort_score
          }
        end

        items
      end

      def query_items
        start, finish = period_range

        query_data = RailsPulse::Summary
          .with_tag_filters(@disabled_tags, @show_non_tagged)
          .joins("INNER JOIN rails_pulse_queries ON rails_pulse_queries.id = rails_pulse_summaries.summarizable_id")
          .where(summarizable_type: "RailsPulse::Query", period_start: start..finish)
          .group("rails_pulse_summaries.summarizable_id, rails_pulse_queries.normalized_sql")
          .select(
            "rails_pulse_summaries.summarizable_id as query_id",
            "rails_pulse_queries.normalized_sql",
            "SUM(rails_pulse_summaries.p95_duration * rails_pulse_summaries.count) / NULLIF(SUM(rails_pulse_summaries.count), 0) as p95_duration",
            "SUM(rails_pulse_summaries.count) as total_count"
          )

        items = []
        classified_ids = []

        query_data.each do |record|
          p95   = record.p95_duration.to_f
          count = record.total_count.to_i

          severity, reason, metric, metric_sub, sort_score = classify_query(p95, count)
          next unless severity

          classified_ids << record.query_id
          items << {
            type:       "QUERY",
            name:       truncate_sql(record.normalized_sql),
            reason:     reason,
            metric:     metric,
            metric_sub: metric_sub,
            link:       url_helpers.query_path(record.query_id),
            severity:   severity,
            sort_score: sort_score,
            monospace:  true
          }
        end

        # Also surface analyzed queries with detected critical issues
        RailsPulse::Query
          .where.not(analyzed_at: nil)
          .where.not(issues: [ nil, "", "[]" ])
          .find_each do |query|
            next if classified_ids.include?(query.id)
            next unless query.critical_issues_count > 0

            critical_count = query.critical_issues_count
            items << {
              type:       "QUERY",
              name:       truncate_sql(query.normalized_sql),
              reason:     "#{critical_count} critical issue#{critical_count == 1 ? "" : "s"} detected",
              metric:     "#{critical_count} critical issue#{critical_count == 1 ? "" : "s"}",
              metric_sub: query.warning_issues_count > 0 ? "#{query.warning_issues_count} warning#{query.warning_issues_count == 1 ? "" : "s"}" : "analyzed",
              link:       url_helpers.query_path(query.id),
              severity:   :warning,
              sort_score: critical_count.to_f,
              monospace:  true
            }
          end

        items
      end

      def job_items
        return [] unless RailsPulse.configuration.track_jobs

        items = []
        RailsPulse::Job.where("runs_count > 0").each do |job|
          failure_rate = job.failure_rate
          p95          = job.p95_duration.to_f

          severity, reason, metric, metric_sub, sort_score = classify_job(
            failure_rate, p95, job.runs_count, job.failures_count, job.queue_name.presence || "default"
          )
          next unless severity

          items << {
            type:       "JOB",
            name:       job.name,
            reason:     reason,
            metric:     metric,
            metric_sub: metric_sub,
            link:       url_helpers.job_path(job.id),
            severity:   severity,
            sort_score: sort_score
          }
        end

        items
      end

      # Exception groups that fired often enough over the period to be worth
      # looking at. Read from summaries, not from ExceptionGroup#occurrence_count
      # — that is a lifetime counter, so a group that was noisy last year and is
      # silent now would otherwise be reported forever.
      #
      # Ignored groups are excluded by design: a user marking something ignored
      # is saying "stop telling me about this", and the attention list is
      # exactly where that must be honoured.
      def exception_items
        return [] unless RailsPulse.configuration.track_exceptions
        return [] unless exception_tables_available?

        start, finish = period_range

        counts = RailsPulse::Summary
          .for_exceptions
          .where.not(summarizable_id: 0)
          .where(period_start: start..finish)
          .group(:summarizable_id)
          .sum(:count)

        return [] if counts.empty?

        groups = RailsPulse::ExceptionGroup
          .where(id: counts.keys, status: "open")
          .index_by(&:id)

        counts.filter_map do |group_id, occurrences|
          group = groups[group_id]
          next if group.nil?

          severity = exception_severity(occurrences)
          next if severity.nil?

          {
            type:       "EXCEPTION",
            name:       group.exception_class,
            reason:     "#{occurrences} occurrence#{occurrences == 1 ? "" : "s"}#{group.location.present? ? " · #{group.location}" : ""}",
            metric:     "#{occurrences} this period",
            metric_sub: group.last_seen_at ? "last seen #{time_ago_phrase(group.last_seen_at)}" : "open",
            link:       url_helpers.exception_path(group.id),
            severity:   severity,
            sort_score: occurrences.to_f
          }
        end
      end

      def exception_severity(occurrences)
        return :critical if occurrences >= @exception_thresholds[:critical]
        return :warning  if occurrences >= @exception_thresholds[:warning]

        nil
      end

      def time_ago_phrase(time)
        seconds = (Time.current - time).to_i
        return "just now" if seconds < 60
        return "#{seconds / 60}m ago" if seconds < 3600
        return "#{seconds / 3600}h ago" if seconds < 86_400

        "#{seconds / 86_400}d ago"
      end

      # The exception tables arrive in a migration, so a host that has upgraded
      # the gem but not yet run migrations must still get a working dashboard.
      def exception_tables_available?
        RailsPulse::ExceptionGroup.table_exists?
      rescue ActiveRecord::ActiveRecordError
        false
      end
    end
  end
end
