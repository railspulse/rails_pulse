require "test_helper"

module RailsPulse
  module Cloud
    class PreviewTest < ActiveSupport::TestCase
      setup do
        Summary.delete_all
        @settings = Configuration::CloudSettings.new
      end

      # Structure Tests

      test "previews the latest summarized hour as it would be sent" do
        hour = 2.hours.ago.beginning_of_hour
        Summary.create!(summarizable_type: "RailsPulse::Request", summarizable_id: 0, period_type: "hour",
                        period_start: hour, period_end: hour + 1.hour, count: 12)
        preview = Preview.new(settings: @settings)
        batch = preview.batches.first.to_h

        assert_equal hour, preview.hour
        assert_equal 1, batch[:contract]
        assert_equal @settings.environment, batch[:environment]
        assert_equal 12, batch[:items].find { |item| item[:kind] == "requests" }[:count]
      end

      test "the printout says sending is off until the key and application are set" do
        output = Preview.new(settings: @settings).render

        assert_includes output, "Not sending"
        assert_includes output, "no network calls"
      end

      test "the printout names where it would send once configured, and warns about deployment metadata" do
        hour = 2.hours.ago.beginning_of_hour
        Summary.create!(summarizable_type: "RailsPulse::Request", summarizable_id: 0, period_type: "hour",
                        period_start: hour, period_end: hour + 1.hour, count: 1)
        @settings.api_key = "rpc_4f9Kx2mQ8vTzL1nB7wYc3HdR6sJe5PaU"
        @settings.application = "shop"
        output = Preview.new(settings: @settings).render

        assert_includes output, "https://ingest.railspulse.com as shop"
        assert_includes output, Preview::METADATA_NOTICE
        assert_includes output, %("kind": "requests")
        assert_not_includes output, "4f9Kx2mQ"
      end

      # Edge Cases

      test "with no summarized hour there is no hourly batch, only the health update" do
        preview = Preview.new(settings: @settings)

        assert_nil preview.hour
        assert_empty preview.batches
        assert_includes preview.render, "No hour has been summarized yet"
        assert_includes preview.render, %("type": "health")
      end
    end
  end
end
