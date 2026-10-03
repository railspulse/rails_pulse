module RailsPulse
  # The routes, queries and jobs that need attention over one summary period
  # (an hour, day, week or month), read from that period's own summary rows so
  # every P95 is the period's real one rather than a blend of shorter periods.
  # Classified by the same rules as the dashboard's Needs Attention panel and
  # capped the same way: critical first, MAX_ITEMS in all.
  #
  # Served by GET api/v1/insights; items carry the record's id rather than a
  # dashboard link.
  class PeriodInsights
    include RailsPulse::Dashboard::Concerns::AttentionClassification

    MAX_ITEMS = 10

    def initialize(period_type:, period_start:)
      @period_type      = period_type
      @period_start     = period_start
      @route_thresholds = RailsPulse.configuration.route_thresholds
      @query_thresholds = RailsPulse.configuration.query_thresholds
      @job_thresholds   = RailsPulse.configuration.job_thresholds
    end

    def to_insights_data
      items    = route_items + query_items + job_items
      critical = items.select { |i| i[:severity] == :critical }.sort_by { |i| -i[:sort_score] }
      warning  = items.select { |i| i[:severity] == :warning  }.sort_by { |i| -i[:sort_score] }
      capped   = (critical + warning).first(MAX_ITEMS).map { |i| i.except(:sort_score) }

      {
        critical: capped.select { |i| i[:severity] == :critical },
        warning:  capped.select { |i| i[:severity] == :warning },
        total:    capped.size
      }
    end

    private

    def summaries(type)
      RailsPulse::Summary.where(summarizable_type: type, period_type: @period_type, period_start: @period_start)
    end

    def route_items
      route_data = summaries("RailsPulse::Route")
        .joins("INNER JOIN rails_pulse_routes ON rails_pulse_routes.id = rails_pulse_summaries.summarizable_id")
        .select(
          "rails_pulse_summaries.summarizable_id as route_id",
          "rails_pulse_routes.path",
          "rails_pulse_routes.http_methods as http_methods_raw",
          "rails_pulse_summaries.p95_duration",
          "rails_pulse_summaries.count",
          "rails_pulse_summaries.error_count"
        )

      route_data.filter_map do |record|
        p95        = record.p95_duration.to_f
        total      = record.count.to_i
        errors     = record.error_count.to_i
        error_rate = total > 0 ? (errors * 100.0 / total).round(1) : 0.0

        severity, reason, metric, metric_sub, sort_score = classify_route(p95, total, errors, error_rate, "this period")
        next unless severity

        item("route", record.route_id, "#{http_methods(record.http_methods_raw).join('|')} #{record.path}".strip,
             severity, reason, metric, metric_sub, sort_score)
      end
    end

    def query_items
      query_data = summaries("RailsPulse::Query")
        .joins("INNER JOIN rails_pulse_queries ON rails_pulse_queries.id = rails_pulse_summaries.summarizable_id")
        .select(
          "rails_pulse_summaries.summarizable_id as query_id",
          "rails_pulse_queries.normalized_sql",
          "rails_pulse_summaries.p95_duration",
          "rails_pulse_summaries.count"
        )

      query_data.filter_map do |record|
        severity, reason, metric, metric_sub, sort_score = classify_query(record.p95_duration.to_f, record.count.to_i)
        next unless severity

        item("query", record.query_id, truncate_sql(record.normalized_sql), severity, reason, metric, metric_sub, sort_score)
      end
    end

    def job_items
      return [] unless RailsPulse.configuration.track_jobs

      job_data = summaries("RailsPulse::Job")
        .joins("INNER JOIN rails_pulse_jobs ON rails_pulse_jobs.id = rails_pulse_summaries.summarizable_id")
        .select(
          "rails_pulse_summaries.summarizable_id as job_id",
          "rails_pulse_jobs.name as job_name",
          "rails_pulse_jobs.queue_name",
          "rails_pulse_summaries.p95_duration",
          "rails_pulse_summaries.count",
          "rails_pulse_summaries.error_count"
        )

      job_data.filter_map do |record|
        runs         = record.count.to_i
        failures     = record.error_count.to_i
        failure_rate = runs > 0 ? (failures * 100.0 / runs).round(1) : 0.0

        severity, reason, metric, metric_sub, sort_score = classify_job(
          failure_rate, record.p95_duration.to_f, runs, failures, record.queue_name.presence || "default"
        )
        next unless severity

        item("job", record.job_id, record.job_name, severity, reason, metric, metric_sub, sort_score)
      end
    end

    def item(type, id, name, severity, reason, metric, metric_sub, sort_score)
      { type: type, id: id, name: name, severity: severity, reason: reason,
        metric: metric, metric_sub: metric_sub, sort_score: sort_score }
    end

    def http_methods(raw)
      Array(JSON.parse(raw.to_s))
    rescue JSON::ParserError
      []
    end
  end
end
