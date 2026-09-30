module RailsPulse
  module Api
    module V1
      class JobsController < BaseController
        STATUSES = %w[failed].freeze

        def index
          parsed_range = time_range
          return unless parsed_range
          since_start, until_end = parsed_range

          collection = RailsPulse::Job.all.order(:name, :id)
          collection = collection.where(name: params[:job]) if params[:job].present?

          status = params[:status].presence
          if status && !STATUSES.include?(status)
            return render json: { error: "Invalid status. Valid values: #{STATUSES.join(', ')}" }, status: :bad_request
          end

          return render_windowed(collection, since_start, until_end, failed_only: status == "failed") if since_start || until_end

          collection = collection.with_failures if status == "failed"
          data, meta = paginated(collection)
          render json: { data: data.map { |job| JobSerializer.serialize(job) }, meta: meta }
        end

        private

        # Job rows carry lifetime counters, so a windowed question is answered
        # from the per-job summaries the summary service writes each period,
        # plus the raw runs recorded since the last period it summarized.
        # Returning the lifetime numbers instead would answer a different
        # question without saying so.
        def render_windowed(collection, since_start, until_end, failed_only:)
          until_end ||= Time.current
          since_start ||= until_end - 24.hours

          # Hourly rows are pruned at hourly_summary_retention, so a window
          # reaching past that is read from daily rows for its whole length:
          # reading the hourly rows that survive would count only part of it.
          period_type = since_start >= RailsPulse.configuration.hourly_summary_retention.ago ? "hour" : "day"

          # Periods are bucketed in the application's time zone, so the window
          # is widened to that zone's period boundaries, not UTC ones.
          from = RailsPulse::Summary.normalize_period_start(period_type, since_start.in_time_zone)
          summarized_through = summarized_through(period_type)
          summary_to = summarized_through ? [ summarized_through, period_ceiling(period_type, until_end) ].min : from
          summary_to = from if summary_to < from

          # The runs after the last summarized period are not in any summary
          # yet, so they are counted from the raw rows. Cleanup never deletes a
          # run that has not been summarized, so they are all still there.
          live_from = [ from, summary_to ].max
          live = live_from < until_end ? live_rows(collection, live_from, until_end) : {}
          summarized = summary_to > from ? summary_rows(collection, period_type, from, summary_to) : {}

          jobs = RailsPulse::Job.where(id: summarized.keys | live.keys).index_by(&:id)
          rows = jobs.values.map { |job| [ job, stats_for(summarized[job.id], live[job.id]) ] }
          rows.select! { |_, stats| stats[:failures_count].positive? } if failed_only
          rows.sort_by! { |job, _| [ job.name.to_s, job.id ] }

          page = rows.drop(offset).first(limit)

          window = { since: from.utc.iso8601, until: [ summary_to, until_end ].max.utc.iso8601, period_type: period_type }
          window[:summarized_through] = summarized_through&.utc&.iso8601
          window[:live_from] = live_from.utc.iso8601 if live_from < until_end

          render json: {
            data: page.map { |job, stats| JobSerializer.serialize(job, stats: stats) },
            meta: { total: rows.size, limit: limit, offset: offset, window: window }
          }
        end

        # The end of the newest period SummaryJob has written. The overall
        # request row is written every period even when nothing ran, so it
        # advances on an app that records no requests between job runs.
        def summarized_through(period_type)
          latest = [
            RailsPulse::Summary.overall_requests.for_period_type(period_type).maximum(:period_start),
            RailsPulse::Summary.for_jobs.for_period_type(period_type).maximum(:period_start)
          ].compact.max
          latest && advance(period_type, latest.in_time_zone)
        end

        def summary_rows(collection, period_type, from, to)
          RailsPulse::Summary
            .for_jobs
            .where(period_type: period_type, period_start: from...to)
            .where(summarizable_id: collection.select(:id))
            .group(:summarizable_id)
            .select(
              "summarizable_id, COUNT(*) AS periods, SUM(count) AS runs, SUM(error_count) AS failures, " \
              "SUM(total_duration) AS total_duration, MIN(min_duration) AS min_duration, " \
              "MAX(max_duration) AS max_duration, MAX(p95_duration) AS p95_duration, " \
              "MAX(p99_duration) AS p99_duration"
            )
            .index_by(&:summarizable_id)
        end

        # Counted the way SummaryService counts a period: finished runs only,
        # and anything other than success is a failure.
        def live_rows(collection, from, to)
          failure = "CASE WHEN status = #{RailsPulse::JobRun.connection.quote('success')} THEN 0 ELSE 1 END"

          RailsPulse::JobRun
            .where(occurred_at: from...to, status: RailsPulse::JobRun::FINAL_STATUSES)
            .where(job_id: collection.select(:id))
            .group(:job_id)
            .select(
              "job_id, COUNT(*) AS runs, SUM(#{failure}) AS failures, SUM(duration) AS total_duration, " \
              "MIN(duration) AS min_duration, MAX(duration) AS max_duration"
            )
            .index_by(&:job_id)
        end

        def stats_for(summarized, live)
          sources = [ summarized, live ].compact
          runs = sources.sum { |row| row.runs.to_i }
          failures = sources.sum { |row| row.failures.to_i }
          total_duration = sources.sum { |row| row.total_duration.to_f }

          stats = {
            runs_count:     runs,
            failures_count: failures,
            failure_rate:   runs > 0 ? ((failures.to_f / runs) * 100).round(2) : 0.0,
            avg_duration:   runs > 0 ? (total_duration / runs).round(2) : nil,
            min_duration:   sources.filter_map { |row| row.min_duration&.to_f }.min&.round(2),
            max_duration:   sources.filter_map { |row| row.max_duration&.to_f }.max&.round(2)
          }

          # A percentile is a property of a distribution, and the distribution
          # behind each period is not kept, so percentiles from several periods
          # cannot be combined. They are reported only when one summarized
          # period holds every run in the window.
          periods = summarized&.periods.to_i
          if periods == 1 && live.nil?
            stats[:p95_duration] = summarized.p95_duration&.to_f&.round(2)
            stats[:p99_duration] = summarized.p99_duration&.to_f&.round(2)
          else
            stats[:percentiles_note] = percentiles_note(periods, live)
          end

          stats
        end

        def percentiles_note(periods, live)
          if live && periods.zero?
            "Omitted: these runs have not been summarized yet, and percentiles are read from summaries. " \
              "Request a window ending at or before meta.window.summarized_through for p95 and p99."
          else
            spans = live ? "#{periods} summary period(s) and runs not yet summarized" : "#{periods} summary periods"
            "Omitted: the window spans #{spans}, which cannot be combined into one percentile. " \
              "Request a window covering a single summarized period for p95 and p99."
          end
        end

        # The start of the period after the one `time` falls in, or `time`
        # itself when it is already on a boundary.
        def period_ceiling(period_type, time)
          start = RailsPulse::Summary.normalize_period_start(period_type, time.in_time_zone)
          start == time ? start : advance(period_type, start)
        end

        # Calendar arithmetic in the application's zone, so a day is a day
        # across a DST change.
        def advance(period_type, time)
          period_type == "hour" ? time + 1.hour : time + 1.day
        end
      end
    end
  end
end
