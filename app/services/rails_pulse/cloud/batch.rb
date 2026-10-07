require "zlib"
require "securerandom"

module RailsPulse
  module Cloud
    # Items wrapped in the envelope the sync contract defines, split so no
    # batch exceeds what Cloud accepts. Each batch gets its own `batch_id`
    # when it is built; a retry resends the same one, which is how Cloud
    # tells a resend from new data.
    class Batch
      CONTRACT = 1
      MAX_ITEMS = 5_000
      MAX_COMPRESSED_BYTES = 1_000_000

      attr_reader :envelope, :items, :batch_id

      # @param items [Array<Hash>]
      # @param envelope [Hash] the fields every batch repeats (see .envelope)
      # @return [Array<Batch>] one or more batches, none over the limits
      def self.build(items, envelope:)
        items.each_slice(MAX_ITEMS).flat_map { |slice| fitting(slice, envelope) }
      end

      # Halves a batch until each part compresses under the limit. A single
      # item larger than the limit is left as a batch of one; Cloud refuses
      # it, which is the right outcome for an item that cannot be sent.
      def self.fitting(items, envelope)
        batch = new(items, envelope: envelope)
        return [ batch ] if items.size <= 1 || batch.compressed_bytesize <= MAX_COMPRESSED_BYTES

        middle = items.size / 2
        fitting(items.first(middle), envelope) + fitting(items.drop(middle), envelope)
      end

      # The envelope fields that identify where a batch came from.
      def self.envelope(application:, environment:, installation_id:)
        {
          contract: CONTRACT,
          application: application,
          environment: environment,
          installation_id: installation_id,
          time_zone: Time.zone.tzinfo.name,
          gem_version: RailsPulse::VERSION,
          rails_version: Rails.version,
          ruby_version: RUBY_VERSION,
          database_adapter: RailsPulse::ApplicationRecord.connection_db_config.adapter.to_s
        }
      end

      # A UUID version 7: a millisecond timestamp followed by random bits, so
      # batch IDs sort by when they were built.
      def self.uuid_v7(time = Time.current)
        return SecureRandom.uuid_v7 if SecureRandom.respond_to?(:uuid_v7)

        milliseconds = (time.to_r * 1000).to_i
        bytes = [ milliseconds >> 16, milliseconds & 0xffff ].pack("Nn").bytes + SecureRandom.random_bytes(10).bytes
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        hex = bytes.pack("C*").unpack1("H*")
        [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
      end

      def initialize(items, envelope:, batch_id: self.class.uuid_v7, sent_at: Time.current)
        @items = items
        @envelope = envelope
        @batch_id = batch_id
        @sent_at = sent_at
      end

      def to_h
        { contract: CONTRACT, batch_id: @batch_id, sent_at: @sent_at.utc.iso8601, **@envelope.except(:contract), items: @items }
      end

      def to_json(*)
        to_h.to_json
      end

      def compressed_bytesize
        Zlib.gzip(to_json).bytesize
      end
    end
  end
end
