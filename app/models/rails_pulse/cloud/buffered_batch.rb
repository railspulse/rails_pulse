require "zlib"

module RailsPulse
  module Cloud
    # A batch waiting to be sent to Rails Pulse Cloud, stored gzipped. It
    # keeps its batch_id across retries, so Cloud recognises a resend. The
    # buffer holds at most MAX_AGE or MAX_BYTES of batches, dropping the
    # oldest first, so an outage cannot grow it without bound.
    class BufferedBatch < RailsPulse::ApplicationRecord
      self.table_name = "rails_pulse_cloud_batches"

      MAX_AGE = 7.days
      MAX_BYTES = 50.megabytes

      validates :batch_id, :payload, :byte_size, :item_count, :next_attempt_at, presence: true

      scope :due, ->(now = Time.current) { where(next_attempt_at: ..now).order(:created_at, :id) }

      def self.ransackable_attributes(_auth_object = nil)
        %w[batch_id byte_size item_count attempts next_attempt_at created_at]
      end

      def self.ransackable_associations(_auth_object = nil)
        []
      end

      def self.enqueue!(batch, now: Time.current)
        payload = Zlib.gzip(batch.to_json)
        create!(batch_id: batch.batch_id, payload: payload, byte_size: payload.bytesize, item_count: batch.items.size,
                next_attempt_at: now)
      end

      # Drops batches past MAX_AGE, then the oldest until the rest fit in
      # MAX_BYTES. Returns how many were dropped.
      def self.prune!(now = Time.current)
        dropped = where(created_at: ...(now - MAX_AGE)).delete_all
        total = sum(:byte_size)
        return dropped if total <= MAX_BYTES

        order(:created_at, :id).pluck(:id, :byte_size).each do |id, size|
          break if total <= MAX_BYTES

          dropped += where(id: id).delete_all
          total -= size
        end
        dropped
      end

      # The stored batch as a hash with string keys.
      def contents
        JSON.parse(Zlib.gunzip(payload))
      end
    end
  end
end
