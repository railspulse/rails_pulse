module RailsPulse
  module Dashboard
    class NeedsAttention
      CRITICAL_ERROR_RATE       = 10.0
      WARNING_ERROR_RATE        = 5.0
      CRITICAL_JOB_FAILURE_RATE = 10.0
      WARNING_JOB_FAILURE_RATE  = 5.0

      def initialize(disabled_tags: [], show_non_tagged: true, period: 7, period_type: @period_type)
        @disabled_tags    = disabled_tags
        @show_non_tagged  = show_non_tagged
        @period           = period
        @period_type      = period_type
        @route_thresholds = RailsPulse.configuration.route_thresholds
        @query_thresholds = RailsPulse.configuration.query_thresholds
        @job_thresholds   = RailsPulse.configuration.job_thresholds
      end

      MAX_ITEMS = 10

      def to_attention_data
        items    = route_items + query_items + job_items
        critical = items.select { |i| i[:severity] == :critical }.sort_by { |i| -i[:sort_score] }
        warning  = items.select { |i| i[:severity] == :warning  }.sort_by { |i| -i[:sort_score] }

        capped = (critical + warning).first(MAX_ITEMS)

        {
          critical: capped.select { |i| i[:severity] == :critical },
          warning:  capped.select { |i| i[:severity] == :warning },
          total:    capped.size
        }
      end

      private

      def period_range
        [ @period.days.ago.beginning_of_day, Time.current ]
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

          severity, reason, metric, metric_sub, sort_score = classify_route(p95, total, errors, error_rate)
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

      def classify_route(p95, total, errors, error_rate)
        if p95 >= @route_thresholds[:critical] || error_rate >= CRITICAL_ERROR_RATE
          if error_rate >= CRITICAL_ERROR_RATE
            [ :critical,
              "#{error_rate}% error rate · #{total} requests this week",
              "#{errors} errors",
              "P95 #{p95.round(0).to_i}ms",
              errors * total.to_f ]
          else
            [ :critical,
              "#{p95.round(0).to_i}ms P95 · exceeds #{@route_thresholds[:critical]}ms threshold",
              "#{p95.round(0).to_i}ms P95",
              "#{total} requests",
              p95 ]
          end
        elsif p95 >= @route_thresholds[:slow] || error_rate >= WARNING_ERROR_RATE
          if error_rate >= WARNING_ERROR_RATE && p95 < @route_thresholds[:slow]
            [ :warning,
              "#{error_rate}% error rate · #{total} requests this week",
              "#{errors} errors",
              "P95 #{p95.round(0).to_i}ms",
              errors * total.to_f ]
          else
            [ :warning,
              "#{p95.round(0).to_i}ms P95 · #{error_rate > 0 ? "#{error_rate}% error rate" : "above slow threshold"}",
              "#{p95.round(0).to_i}ms P95",
              "#{total} requests",
              p95 ]
          end
        end
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

          if p95 >= @query_thresholds[:critical]
            severity = :critical
            reason   = "#{p95.round(0).to_i}ms P95 · exceeds #{@query_thresholds[:critical]}ms threshold"
          elsif p95 >= @query_thresholds[:slow]
            severity = :warning
            reason   = "#{p95.round(0).to_i}ms P95 · above #{@query_thresholds[:slow]}ms slow threshold"
          else
            next
          end

          classified_ids << record.query_id
          items << {
            type:       "QUERY",
            name:       truncate_sql(record.normalized_sql),
            reason:     reason,
            metric:     "#{p95.round(0).to_i}ms P95",
            metric_sub: "#{count} execution#{count == 1 ? "" : "s"}",
            link:       url_helpers.query_path(record.query_id),
            severity:   severity,
            sort_score: p95,
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

          severity, reason, metric, metric_sub, sort_score = classify_job(job, failure_rate, p95)
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

      def classify_job(job, failure_rate, p95)
        if failure_rate >= CRITICAL_JOB_FAILURE_RATE || p95 >= @job_thresholds[:critical]
          if failure_rate >= CRITICAL_JOB_FAILURE_RATE
            [ :critical,
              "#{job.queue_name.presence || "default"} queue · #{failure_rate}% failure rate",
              "#{job.failures_count} / #{job.runs_count} failed",
              "P95 #{p95.round(0).to_i}ms",
              job.failures_count * job.runs_count.to_f ]
          else
            [ :critical,
              "P95 #{p95.round(0).to_i}ms · exceeds #{@job_thresholds[:critical]}ms threshold",
              "#{p95.round(0).to_i}ms P95",
              "#{job.runs_count} runs",
              p95 ]
          end
        elsif failure_rate >= WARNING_JOB_FAILURE_RATE || p95 >= @job_thresholds[:slow]
          if failure_rate >= WARNING_JOB_FAILURE_RATE
            [ :warning,
              "#{job.queue_name.presence || "default"} queue · #{failure_rate}% failure rate",
              "#{job.failures_count} / #{job.runs_count} failed",
              "P95 #{p95.round(0).to_i}ms",
              job.failures_count * job.runs_count.to_f ]
          else
            [ :warning,
              "P95 #{p95.round(0).to_i}ms · above slow threshold",
              "#{p95.round(0).to_i}ms P95",
              "#{job.runs_count} runs",
              p95 ]
          end
        end
      end

      def truncate_sql(sql)
        return "" if sql.blank?
        cleaned = sql.gsub(/\s+/, " ").strip
        cleaned.length > 80 ? "#{cleaned[0..79]}..." : cleaned
      end
    end
  end
end
