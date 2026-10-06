require "test_helper"

module RailsPulse
  module Cloud
    class BatchTest < ActiveSupport::TestCase
      ENVELOPE = { contract: 1, application: "shop", environment: "production", installation_id: nil }.freeze

      # Structure Tests

      test "a batch carries the contract version, its own id and the envelope" do
        hash = Batch.new([ { type: "health" } ], envelope: ENVELOPE).to_h

        assert_equal 1, hash[:contract]
        assert_match(/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/, hash[:batch_id])
        assert_equal "shop", hash[:application]
        assert_equal [ { type: "health" } ], hash[:items]
      end

      test "the envelope names this installation's versions, zone and adapter" do
        envelope = Batch.envelope(application: "shop", environment: "production", installation_id: "5b0c7e1a-2f3d-4e5a-8b6c-7d8e9f0a1b2c")

        assert_equal RailsPulse::VERSION, envelope[:gem_version]
        assert_equal Rails.version, envelope[:rails_version]
        assert_equal RUBY_VERSION, envelope[:ruby_version]
        assert_equal Time.zone.tzinfo.name, envelope[:time_zone]
        assert_equal RailsPulse::ApplicationRecord.connection_db_config.adapter, envelope[:database_adapter]
      end

      # Calculation Tests

      test "items are split into batches of at most 5,000" do
        batches = Batch.build(Array.new(12_001) { |n| { n: n } }, envelope: ENVELOPE)

        assert_equal [ 5_000, 5_000, 2_001 ], batches.map { |batch| batch.items.size }
        assert_equal 3, batches.map { |batch| batch.to_h[:batch_id] }.uniq.size
      end

      test "a batch over the compressed limit is halved until each part fits" do
        items = Array.new(6) { { noise: SecureRandom.base64(200_000) } }
        batches = Batch.build(items, envelope: ENVELOPE)

        assert_operator batches.size, :>, 1
        assert_equal items, batches.flat_map(&:items)
        batches.each { |batch| assert_operator batch.compressed_bytesize, :<=, Batch::MAX_COMPRESSED_BYTES }
      end

      test "a UUID v7 built without SecureRandom.uuid_v7 starts with the time" do
        time = Time.utc(2026, 10, 4, 10, 5, 12)
        SecureRandom.stubs(:respond_to?).with(:uuid_v7).returns(false)
        uuid = Batch.uuid_v7(time)

        assert_match(/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/, uuid)
        assert_equal (time.to_r * 1000).to_i, uuid.delete("-")[0, 12].to_i(16)
      end

      # Edge Cases

      test "no items build no batches" do
        assert_empty Batch.build([], envelope: ENVELOPE)
      end

      test "a single item over the limit is left as a batch of its own" do
        item = { noise: SecureRandom.base64(1_000_000) }

        assert_equal [ [ item ] ], Batch.build([ item ], envelope: ENVELOPE).map(&:items)
      end
    end
  end
end
