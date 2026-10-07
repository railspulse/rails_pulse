require "test_helper"

module RailsPulse
  module Cloud
    class SyncTest < ActiveSupport::TestCase
      fixtures :rails_pulse_exception_groups

      # Answers each post with the next response given (the last repeats) and
      # keeps every batch it was sent.
      class FakeClient
        attr_reader :batches

        def initialize(*responses)
          @responses = responses
          @batches = []
        end

        def post(body)
          @batches << JSON.parse(body)
          response = @responses.size > 1 ? @responses.shift : @responses.first
          raise response if response.is_a?(Exception)

          response
        end
      end

      setup do
        travel_to Time.zone.local(2026, 10, 6, 12, 10)
        Summary.delete_all
        Installation.delete_all
        BufferedBatch.delete_all
        ExceptionGroup.update_all(updated_at: 30.days.ago)
        Deployment.delete_all
        @settings = Configuration::CloudSettings.new
        @settings.api_key = "rpc_4f9Kx2mQ8vTzL1nB7wYc3HdR6sJe5PaU"
        @settings.application = "shop"
        summarize(Time.zone.local(2026, 10, 6, 11))
      end

      teardown do
        travel_back
      end

      # Structure Tests

      test "does nothing at all while config.cloud is unset" do
        client = FakeClient.new(response(202))

        assert_equal :disabled, sync(Configuration::CloudSettings.new, client).hourly
        assert_equal :disabled, sync(Configuration::CloudSettings.new, client).minutely
        assert_empty client.batches
        assert_equal 0, Installation.count
      end

      test "the first hourly sync sends the latest summarized hour and clears the buffer" do
        client = FakeClient.new(response(202))

        assert_equal :ok, sync(@settings, client).hourly

        batch = client.batches.first

        assert_equal 1, client.batches.size
        assert_equal "shop", batch["application"]
        assert_equal Installation.first.installation_id, batch["installation_id"]
        assert_equal [ Time.zone.local(2026, 10, 6, 11).utc.iso8601 ], batch["items"].filter_map { |item| item["period_start"] }.uniq
        assert_equal 0, BufferedBatch.count
        assert_equal Time.current, Installation.first.last_success_at
      end

      test "a later hourly sync sends only the hours after the last one sent" do
        sync(@settings, FakeClient.new(response(202))).hourly
        summarize(Time.zone.local(2026, 10, 6, 12))
        travel 1.hour
        client = FakeClient.new(response(202))

        sync(@settings, client).hourly

        assert_equal [ Time.zone.local(2026, 10, 6, 12).utc.iso8601 ], client.batches.flat_map { |batch| batch["items"] }.filter_map { |item| item["period_start"] }.uniq
      end

      test "exception groups and deployments changed since the last sync are sent once" do
        sync(@settings, FakeClient.new(response(202))).hourly
        travel 5.minutes
        rails_pulse_exception_groups(:zero_division).update!(status: "resolved")
        Deployment.create!(revision: "a1b2c3d", started_at: 1.minute.ago)
        travel 1.minute
        client = FakeClient.new(response(202))

        sync(@settings, client).hourly
        types = client.batches.flat_map { |batch| batch["items"] }.map { |item| item["type"] }

        assert_equal %w[deployment exception_group], types.sort
        assert_empty(sync(@settings, client).tap(&:hourly) && client.batches.drop(1))
      end

      # Calculation Tests

      test "a batch Cloud rejects as malformed is dropped and the next one is still sent" do
        2.times { |n| buffer(n) }
        client = FakeClient.new(response(400, code: "malformed", message: "items must be an array"), response(202))

        flush(client)

        assert_equal 2, client.batches.size
        assert_equal 0, BufferedBatch.count
      end

      test "a dropped malformed batch is recorded for rails_pulse:status" do
        buffer(0)
        flush(FakeClient.new(response(400, code: "malformed", message: "items must be an array")))

        assert_equal 0, BufferedBatch.count
        assert_includes Installation.first.last_error, "items must be an array"
      end

      test "a refused key pauses sending, keeps buffering, and retries after an hour" do
        client = FakeClient.new(response(401, code: "invalid_api_key", message: "That key has been revoked."))

        sync(@settings, client).hourly
        installation = Installation.first

        assert_predicate installation, :paused?
        assert_equal Time.current + 1.hour, installation.paused_until
        assert_includes installation.pause_reason, "refused config.cloud.api_key: That key has been revoked."
        assert_equal 1, BufferedBatch.count

        summarize(Time.zone.local(2026, 10, 6, 12))
        travel 30.minutes
        sync(@settings, client).hourly

        assert_equal 1, client.batches.size
        assert_equal 2, BufferedBatch.count

        travel 31.minutes
        resumed = FakeClient.new(response(202))
        sync(@settings, resumed).minutely

        assert_equal 2, resumed.batches.count { |batch| batch["items"].none? { |item| item["type"] == "health" } }
        assert_equal 0, BufferedBatch.count
        assert_not_predicate Installation.first, :paused?
      end

      test "an inactive subscription and an unknown application pause with their own message" do
        sync(@settings, FakeClient.new(response(402, message: "Renew at railspulse.com/billing."))).hourly

        assert_includes Installation.first.pause_reason, "subscription is not active: Renew at railspulse.com/billing."

        Installation.delete_all
        sync(@settings, FakeClient.new(response(404, message: "No application shop."))).hourly

        assert_includes Installation.first.pause_reason, %(does not know the application "shop")
      end

      test "an unsupported contract pauses for a day and says to upgrade the gem" do
        sync(@settings, FakeClient.new(response(422, message: "Contract 1 is not supported"))).hourly

        assert_equal Time.current + 1.day, Installation.first.paused_until
        assert_includes Installation.first.pause_reason, "Upgrade the rails_pulse gem"
      end

      test "a batch Cloud finds too large is split into two new batches, both sent" do
        buffer(0, items: Array.new(4) { |n| { type: "deployment", revision: "r#{n}", started_at: Time.current.utc.iso8601 } })
        original = BufferedBatch.first.batch_id
        client = FakeClient.new(response(413), response(202))

        flush(client)
        halves = client.batches.drop(1)

        assert_equal [ 2, 2 ], halves.map { |batch| batch["items"].size }
        assert_not_includes halves.map { |batch| batch["batch_id"] }, original
        assert_equal 0, BufferedBatch.count
      end

      test "a rate limit waits for Retry-After" do
        buffer(0)
        flush(FakeClient.new(response(429, headers: { "retry-after" => "120" })))

        assert_equal Time.current + 120.seconds, BufferedBatch.first.next_attempt_at
      end

      test "an outage backs off from a minute, doubling to an hour, resending the same batch id" do
        buffer(0)
        batch_id = BufferedBatch.first.batch_id
        client = FakeClient.new(response(503))
        delays = []

        8.times do
          flush(client)
          delays << (BufferedBatch.first.next_attempt_at - Time.current).to_i
          travel_to BufferedBatch.first.next_attempt_at
        end

        assert_equal [ 60, 120, 240, 480, 960, 1920, 3600, 3600 ], delays
        assert_equal [ batch_id ], client.batches.map { |batch| batch["batch_id"] }.uniq
        assert_equal 8, BufferedBatch.first.attempts
      end

      test "a connection error is treated as an outage" do
        buffer(0)
        flush(FakeClient.new(Client::Unavailable.new("Net::OpenTimeout: execution expired")))

        assert_equal Time.current + 1.minute, BufferedBatch.first.next_attempt_at
        assert_includes Installation.first.last_error, "execution expired"
      end

      test "a duplicate answer removes the batch like an acceptance" do
        buffer(0)
        flush(FakeClient.new(response(200, duplicate: true)))

        assert_equal 0, BufferedBatch.count
      end

      test "the contract deprecation date is recorded" do
        sync(@settings, FakeClient.new(response(202, headers: { "rails-pulse-contract-deprecated" => "2027-10-01" }))).hourly

        assert_equal "2027-10-01", Installation.first.contract_deprecated_on
      end

      # Health Tests

      test "the minutely run sends a health update without buffering it" do
        client = FakeClient.new(response(503))

        sync(@settings, client).minutely

        assert_equal [ "health" ], client.batches.first["items"].map { |item| item["type"] }
        assert_equal 0, BufferedBatch.count
        assert_includes Installation.first.last_error, "Health update not sent"
      end

      test "the minutely run sends a deployment recorded since the last run" do
        sync(@settings, FakeClient.new(response(202))).minutely
        Deployment.create!(revision: "a1b2c3d", started_at: Time.current)
        travel 1.minute
        client = FakeClient.new(response(202))

        sync(@settings, client).minutely

        assert(client.batches.any? { |batch| batch["items"].any? { |item| item["revision"] == "a1b2c3d" } })
      end

      test "no health update is sent while paused" do
        Installation.current.pause!(1.hour.from_now, "refused")
        client = FakeClient.new(response(202))

        sync(@settings, client).minutely

        assert_empty client.batches
      end

      # Edge Cases

      test "an unexpected error is recorded rather than raised" do
        client = FakeClient.new(RuntimeError.new("boom"))

        assert_equal :failed, sync(@settings, client).hourly
        assert_includes Installation.first.last_error, "boom"
      end

      test "with no summarized hour only the records are queued" do
        Summary.delete_all
        client = FakeClient.new(response(202))

        sync(@settings, client).hourly

        assert(client.batches.flat_map { |batch| batch["items"] }.none? { |item| item["type"] == "summary" })
      end

      private

      def sync(settings, client)
        Sync.new(settings: settings, client: client, now: Time.current, jitter: ->(delay) { delay })
      end

      # An hourly run with no summarized hour and no changed records only
      # sends what is already buffered.
      def flush(client)
        Summary.delete_all
        sync(@settings, client).hourly
      end

      def response(status, headers: {}, **body)
        Client::Response.new(status: status, body: body.to_json, headers: headers)
      end

      def summarize(hour)
        Summary.create!(summarizable_type: "RailsPulse::Request", summarizable_id: 0, period_type: "hour",
                        period_start: hour, period_end: hour + 1.hour, count: 5)
      end

      def buffer(index, items: [ { type: "deployment", revision: "r#{index}", started_at: Time.current.utc.iso8601 } ])
        envelope = Batch.envelope(application: "shop", environment: "test", installation_id: Installation.current.installation_id)
        BufferedBatch.enqueue!(Batch.new(items, envelope: envelope))
      end
    end
  end
end
