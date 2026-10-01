module RailsPulse
  module Api
    module V1
      # What Rails Pulse knows, and how recently, so a caller can tell "nothing
      # went wrong" from "nothing was recorded". Every other endpoint answers a
      # question about the data; this one answers whether the data is there.
      class CoverageController < BaseController
        # A writer silent for longer than this is treated as not collecting,
        # matching the window the dashboard and status task use.
        LIVE_WINDOW = RailsPulse::WriterHeartbeat::LIVE_WINDOW

        # Hourly summaries fall behind by up to an hour in normal operation,
        # so staleness is measured past that.
        SUMMARY_GRACE = 2.hours

        def show
          render json: {
            as_of: Time.current.utc.iso8601,
            telemetry: telemetry,
            summaries: summaries,
            retention: retention,
            collection: collection
          }
        end

        private

        # The newest and oldest record of each kind. An empty pair means
        # nothing of that kind has been recorded — not that nothing happened.
        def telemetry
          config = RailsPulse.configuration
          {
            requests:   config.enabled ? span(RailsPulse::Request, :occurred_at) : untracked("config.enabled is false"),
            job_runs:   config.track_jobs ? span(RailsPulse::JobRun, :occurred_at) : untracked("config.track_jobs is false"),
            exceptions: exception_span
          }
        end

        def untracked(reason)
          { tracked: false, reason: reason }
        end

        def span(model, column)
          oldest = model.minimum(column)
          newest = model.maximum(column)
          {
            oldest: oldest&.utc&.iso8601,
            newest: newest&.utc&.iso8601,
            count: model.count,
            tracked: true
          }
        end

        def exception_span
          return untracked("config.track_exceptions is false") unless RailsPulse.configuration.track_exceptions
          return untracked("the exception tables are missing; run the upgrade generator") unless RailsPulse::ExceptionOccurrence.table_exists?

          span(RailsPulse::ExceptionOccurrence, :occurred_at)
        end

        # Aggregated data outlives raw records, so a question about a window
        # older than raw retention is answered from here or not at all.
        def summaries
          latest = RailsPulse::Summary.overall_requests.for_period_type("hour").maximum(:period_end)
          earliest = RailsPulse::Summary.overall_requests.for_period_type("hour").minimum(:period_start)

          {
            hourly_from: earliest&.utc&.iso8601,
            hourly_through: latest&.utc&.iso8601,
            stale: latest.nil? || (Time.current - latest) > SUMMARY_GRACE,
            note: summary_note(latest)
          }
        end

        def summary_note(latest)
          return "RailsPulse::SummaryJob has never run, so no window can be answered from summaries." if latest.nil?

          age_hours = ((Time.current - latest) / 1.hour).round
          return nil if age_hours <= (SUMMARY_GRACE / 1.hour)

          "RailsPulse::SummaryJob is about #{age_hours}h behind, so recent windows are incomplete."
        end

        # What the configuration will keep, which bounds every question that
        # can still be asked.
        def retention
          config = RailsPulse.configuration
          {
            raw_records: duration_label(config.full_retention_period),
            hourly_summaries: duration_label(config.hourly_summary_retention),
            events: duration_label(config.event_retention_period),
            archiving_enabled: config.archiving_enabled
          }
        end

        def duration_label(value)
          return nil if value.nil?

          seconds = value.respond_to?(:to_i) ? value.to_i : nil
          seconds ? { seconds: seconds, days: (seconds / 86_400.0).round(2) } : nil
        end

        # Gaps: requests a writer dropped because its queue was full, which
        # means the numbers understate what happened. A writer that has gone
        # quiet is not one: it starts with a process's first tracked request
        # and a new one starts on the next, so a missing heartbeat means
        # nothing has been queued, not that something was lost.
        def collection
          unless RailsPulse.configuration.async
            return {
              known: false,
              gap_suspected: false,
              reason: "config.async is false, so requests are written inline: nothing is queued or dropped, " \
                      "and no writer heartbeat is recorded"
            }
          end

          unless RailsPulse::Event.table_available?
            return { known: false, reason: "the events table is missing, so writer heartbeats are not recorded" }
          end

          stats = RailsPulse::WriterHeartbeat.summary(window: 1.hour)
          last_seen = stats[:last_sampled_at]

          {
            known: true,
            live_writers: stats[:processes],
            queue_depth: stats[:queue_depth],
            queue_size: stats[:queue_size],
            dropped_last_hour: stats[:dropped],
            last_heartbeat_at: last_seen&.utc&.iso8601,
            gap_suspected: gap_suspected?(stats, last_seen),
            note: collection_note(stats, last_seen)
          }
        end

        def gap_suspected?(stats, _last_seen)
          stats[:dropped].positive?
        end

        def collection_note(stats, last_seen)
          notes = []
          if last_seen.nil?
            notes << "No writer heartbeat is on record. A writer starts with a process's first tracked request, " \
                     "so the app has had no tracked web traffic, or its web processes are not running."
          elsif (Time.current - last_seen) > LIVE_WINDOW
            notes << "No writer has reported since #{last_seen.utc.iso8601}, so no request has been queued since " \
                     "then: the app has had no tracked web traffic, or its web processes are not running."
          end
          if stats[:dropped].positive?
            notes << "#{stats[:dropped]} request(s) were dropped in the last hour because the writer queue was full, so counts understate traffic."
          end
          notes.any? ? notes.join(" ") : nil
        end
      end
    end
  end
end
