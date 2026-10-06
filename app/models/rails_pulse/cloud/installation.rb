module RailsPulse
  module Cloud
    # The one row naming this Rails Pulse database to Rails Pulse Cloud, and
    # where its sync has got to. Hosts that share the database share the row,
    # so their data is counted once; hosts with separate databases are
    # separate installations, and Cloud adds them together.
    class Installation < RailsPulse::ApplicationRecord
      self.table_name = "rails_pulse_cloud_installations"

      validates :installation_id, presence: true

      def self.ransackable_attributes(_auth_object = nil)
        %w[installation_id last_success_at last_error_at paused_until created_at]
      end

      def self.ransackable_associations(_auth_object = nil)
        []
      end

      # The row, created with a new installation ID the first time it is
      # asked for. A second process creating it at the same moment loses on
      # the unique index and reads the winner's.
      def self.current
        first || create!(installation_id: SecureRandom.uuid)
      rescue ActiveRecord::RecordNotUnique
        first!
      end

      # The row if one exists, without creating it.
      def self.existing
        first
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def paused?(now = Time.current)
        paused_until.present? && paused_until > now
      end

      def record_success!(deprecated_on: nil, now: Time.current)
        update!(last_success_at: now, last_error: nil, last_error_at: nil, paused_until: nil, pause_reason: nil,
                contract_deprecated_on: deprecated_on)
      end

      def record_error!(message, now: Time.current)
        update!(last_error: message.to_s.truncate(2_000), last_error_at: now)
      end

      def pause!(until_time, reason, now: Time.current)
        update!(paused_until: until_time, pause_reason: reason.to_s.truncate(2_000),
                last_error: reason.to_s.truncate(2_000), last_error_at: now)
      end
    end
  end
end
