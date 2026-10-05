module RailsPulse
  # One CleanupService run, stored as an Event of kind cleanup_run: `value`
  # is the rows it deleted, `outcome` completed or failed, and `metadata` the
  # per-table counts and any stages that failed. rails_pulse:status reads the
  # latest to say whether cleanup is running at all; nothing else depends on
  # these rows, so event retention prunes them like any other kind.
  class CleanupRun
    KIND = "cleanup_run".freeze
    SUBJECT = "cleanup".freeze

    class << self
      def events
        RailsPulse::Event.of_kind(KIND)
      end

      def record!(stats:, failed_stages: [], ran_at: Time.current)
        RailsPulse::Event.create!(
          kind:        KIND,
          subject:     SUBJECT,
          outcome:     failed_stages.any? ? "failed" : "completed",
          value:       stats[:total_deleted].to_i,
          occurred_at: ran_at,
          metadata:    { time_based: stats[:time_based], count_based: stats[:count_based], failed_stages: failed_stages }.to_json
        )
      end

      def latest
        events.recent.first
      end
    end
  end
end
