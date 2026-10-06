require "test_helper"

module RailsPulse
  module Cloud
    class PreviewTest < ActiveSupport::TestCase
      setup do
        Summary.delete_all
        Installation.delete_all
        BufferedBatch.delete_all
        @settings = Configuration::CloudSettings.new
        @hour = 2.hours.ago.beginning_of_hour
      end

      # Structure Tests

      test "previews the next hourly sync as it would be sent" do
        summarize(@hour, count: 12)
        preview = Preview.new(settings: @settings)
        batch = preview.batches.first.to_h

        assert_equal [ @hour ], preview.plan.hours
        assert_equal 1, batch[:contract]
        assert_equal @settings.environment, batch[:environment]
        assert_equal 12, batch[:items].find { |item| item[:kind] == "requests" }[:count]
      end

      test "previews only the hours after the last one sent" do
        summarize(@hour - 1.hour)
        summarize(@hour)
        Installation.current.update!(last_hour_sent_at: @hour - 1.hour)

        assert_equal [ @hour ], Preview.new(settings: @settings).plan.hours
      end

      test "previewing writes nothing" do
        summarize(@hour)

        Preview.new(settings: @settings).render

        assert_equal 0, Installation.count
        assert_equal 0, BufferedBatch.count
      end

      test "the printout says sending is off until the key and application are set" do
        output = Preview.new(settings: @settings).render

        assert_includes output, "Not sending"
        assert_includes output, "no network calls"
        assert_includes output, "Installation ID: assigned on the first sync"
      end

      test "the printout names where it sends once configured, and warns about deployment metadata" do
        summarize(@hour)
        @settings.api_key = "rpc_4f9Kx2mQ8vTzL1nB7wYc3HdR6sJe5PaU"
        @settings.application = "shop"
        output = Preview.new(settings: @settings).render

        assert_includes output, "Sending to https://ingest.railspulse.com as shop"
        assert_includes output, Preview::METADATA_NOTICE
        assert_includes output, %("kind": "requests")
        assert_not_includes output, "4f9Kx2mQ"
      end

      # Edge Cases

      test "with no summarized hour there are no summary items, only the health update" do
        preview = Preview.new(settings: @settings)

        assert_empty preview.plan.hours
        assert_includes preview.render, "No newly summarized hour to send"
        assert_includes preview.render, %("type": "health")
      end

      private

      def summarize(hour, count: 1)
        Summary.create!(summarizable_type: "RailsPulse::Request", summarizable_id: 0, period_type: "hour",
                        period_start: hour, period_end: hour + 1.hour, count: count)
      end
    end
  end
end
