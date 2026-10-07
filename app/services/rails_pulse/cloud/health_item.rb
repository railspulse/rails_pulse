module RailsPulse
  module Cloud
    # The `health` item for one minute: request volume, errors and response
    # time across the application, exceptions raised, and each host's
    # writers. It runs every minute, so every read is a range on an indexed
    # occurred_at column over that minute alone.
    class HealthItem
      def self.for_minute_before(time = Time.current)
        window_start = (time - 1.minute).beginning_of_minute
        new(window_start).item
      end

      def initialize(window_start)
        @window = window_start...(window_start + 1.minute)
      end

      def item
        durations, statuses = request_rows
        sorted = durations.compact.sort
        {
          type: "health",
          window_start: @window.begin.utc.iso8601,
          window_end: @window.end.utc.iso8601,
          request_count: durations.size,
          error_count: statuses.count { |status| status.to_i >= 500 },
          avg_duration: sorted.any? ? sorted.sum.to_f / sorted.size : nil,
          p95_duration: Statistics.calculate_percentile(sorted, 0.95)&.to_f,
          exception_count: exception_count,
          hosts: hosts
        }
      end

      private

      def request_rows
        rows = Request.where(occurred_at: @window).pluck(:duration, :status)
        [ rows.map(&:first), rows.map(&:last) ]
      end

      def exception_count
        return 0 unless ExceptionOccurrence.table_exists?

        ExceptionOccurrence.where(occurred_at: @window).count
      end

      # One entry per host from the writer heartbeats: the processes that
      # reported recently, their latest queue depth, and requests dropped
      # inside the minute. Process IDs are not sent.
      def hosts
        return [] unless Event.table_available?

        recent = WriterHeartbeat.events
          .where(occurred_at: (@window.end - WriterHeartbeat::LIVE_WINDOW)...@window.end)
          .recent
          .to_a
        latest_per_process = recent.uniq(&:subject)

        latest_per_process.group_by { |event| host_of(event) }.map do |host, events|
          subjects = events.map(&:subject)
          {
            host: host,
            processes: events.size,
            queue_depth: events.sum { |event| event.metadata_hash["queue_depth"].to_i },
            dropped: recent.select { |event| subjects.include?(event.subject) && @window.cover?(event.occurred_at) }.sum { |event| event.value.to_i },
            last_heartbeat_at: events.map(&:occurred_at).max.utc.iso8601
          }
        end.sort_by { |entry| entry[:host].to_s }
      end

      # config.cloud.host_label when the host set one, otherwise its hostname.
      def host_of(event)
        metadata = event.metadata_hash
        metadata["host_label"].presence || metadata["hostname"].presence || event.subject.to_s.rpartition(":").first
      end
    end
  end
end
