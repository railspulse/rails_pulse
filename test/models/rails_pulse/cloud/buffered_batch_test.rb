require "test_helper"

module RailsPulse
  module Cloud
    class BufferedBatchTest < ActiveSupport::TestCase
      ENVELOPE = { application: "shop", environment: "test", installation_id: "5b0c7e1a-2f3d-4e5a-8b6c-7d8e9f0a1b2c" }.freeze

      setup do
        BufferedBatch.delete_all
      end

      # Structure Tests

      test "a batch is stored gzipped and read back whole" do
        batch = Batch.new([ { type: "health" } ], envelope: ENVELOPE)
        buffered = BufferedBatch.enqueue!(batch)

        assert_equal batch.batch_id, buffered.batch_id
        assert_equal 1, buffered.item_count
        assert_equal buffered.payload.bytesize, buffered.byte_size
        assert_equal [ { "type" => "health" } ], buffered.contents["items"]
      end

      test "due lists batches whose next attempt has come, oldest first" do
        later = enqueue(next_attempt_at: 1.hour.from_now)
        second = enqueue(created_at: 1.minute.ago)
        first = enqueue(created_at: 2.minutes.ago)

        assert_equal [ first, second ], BufferedBatch.due.to_a
        assert_not_includes BufferedBatch.due.to_a, later
      end

      # Calculation Tests

      test "prune drops batches older than seven days" do
        old = enqueue(created_at: 8.days.ago)
        kept = enqueue(created_at: 6.days.ago)

        assert_equal 1, BufferedBatch.prune!

        assert_equal [ kept ], BufferedBatch.all.to_a
        assert_not BufferedBatch.exists?(old.id)
      end

      test "prune drops the oldest batches until the buffer fits in 50 MB" do
        oldest = enqueue(created_at: 3.hours.ago, byte_size: 30.megabytes)
        middle = enqueue(created_at: 2.hours.ago, byte_size: 20.megabytes)
        newest = enqueue(created_at: 1.hour.ago, byte_size: 20.megabytes)

        assert_equal 1, BufferedBatch.prune!

        assert_equal [ middle, newest ], BufferedBatch.order(:created_at).to_a
        assert_not BufferedBatch.exists?(oldest.id)
      end

      # Edge Cases

      test "prune leaves a buffer under both limits alone" do
        enqueue

        assert_equal 0, BufferedBatch.prune!
        assert_equal 1, BufferedBatch.count
      end

      private

      def enqueue(created_at: Time.current, next_attempt_at: Time.current, byte_size: nil)
        buffered = BufferedBatch.enqueue!(Batch.new([ { type: "health" } ], envelope: ENVELOPE))
        buffered.update_columns(created_at: created_at, next_attempt_at: next_attempt_at, byte_size: byte_size || buffered.byte_size)
        buffered
      end
    end
  end
end
