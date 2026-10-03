require "test_helper"
require "rails_pulse/mcp/server"

module RailsPulse
  module Mcp
    class ToolsInsightsTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      class StubClient
        attr_reader :calls

        def initialize(response)
          @response = response
          @calls = []
        end

        def get(path, params = {})
          @calls << [ path, params ]
          @response
        end
      end

      INSIGHTS_RESPONSE = {
        "period" => { "type" => "week", "start" => "2026-06-08T00:00:00Z", "end" => "2026-06-14T23:59:59Z", "summarized" => true },
        "thresholds" => { "routes" => { "slow" => 500, "very_slow" => 1500, "critical" => 3000 } },
        "needs_attention" => {
          "critical" => [ { "type" => "route", "id" => 7, "name" => "GET /checkout", "severity" => "critical", "reason" => "3200ms P95" } ],
          "warning" => [ { "type" => "job", "id" => 3, "name" => "ReportJob", "severity" => "warning", "reason" => "default queue · 6.0% failure rate" } ],
          "total" => 2
        },
        "threshold_recommendations" => [
          { "title" => "Route slow threshold may be too low", "detail" => "...",
            "config_snippet" => "config.route_thresholds = { slow: 750, very_slow: 1500, critical: 3000 }" }
        ]
      }.freeze

      def call(client, **args)
        result = Tools::Insights.call(**args, server_context: { client: client })
        [ result, JSON.parse(result.content.first[:text]) ]
      end

      # Structure Tests

      test "reads the last complete week by default" do
        client = StubClient.new(INSIGHTS_RESPONSE)
        call(client)

        assert_equal [ [ "/insights", { period: "week" } ] ], client.calls
      end

      test "passes period and at through, normalising at to UTC" do
        client = StubClient.new(INSIGHTS_RESPONSE)
        call(client, period: "day", at: "2026-06-10T09:00:00+10:00")

        assert_equal({ period: "day", at: "2026-06-09T23:00:00Z" }, client.calls.first[1])
      end

      test "returns the items, thresholds and recommendations with a summary" do
        _, data = call(StubClient.new(INSIGHTS_RESPONSE))

        assert_equal "GET /checkout", data["needs_attention"]["critical"].first["name"]
        assert_equal 500, data["thresholds"]["routes"]["slow"]
        assert_equal 1, data["threshold_recommendations"].size
        assert_equal "Week starting 2026-06-08T00:00:00Z: 1 critical, 1 warning. 1 threshold change(s) suggested.", data["summary"]
      end

      test "next_steps drill into the first route and the jobs" do
        _, data = call(StubClient.new(INSIGHTS_RESPONSE))

        assert_includes data["next_steps"].first, "rails_pulse_endpoint"
        assert_includes data["next_steps"].first, "route: 7"
        assert(data["next_steps"].any? { |step| step.include?("rails_pulse_jobs") })
        assert(data["next_steps"].any? { |step| step.include?("config_snippet") })
      end

      # Edge Cases

      test "a period not yet summarized says so" do
        response = INSIGHTS_RESPONSE.merge(
          "period" => INSIGHTS_RESPONSE["period"].merge("summarized" => false),
          "needs_attention" => { "critical" => [], "warning" => [], "total" => 0 }
        )
        _, data = call(StubClient.new(response))

        assert_includes data["summary"], "has not been summarized yet"
        assert_includes data["next_steps"].first, "rails_pulse_coverage"
      end

      test "items in a period without its overall row are listed with a caveat" do
        response = INSIGHTS_RESPONSE.merge("period" => INSIGHTS_RESPONSE["period"].merge("summarized" => false))
        _, data = call(StubClient.new(response))

        assert_includes data["summary"], "1 critical, 1 warning"
        assert_includes data["summary"], "may be incomplete"
        assert_includes data["next_steps"].first, "rails_pulse_endpoint"
      end

      test "nothing past its thresholds suggests comparing an earlier period" do
        response = INSIGHTS_RESPONSE.merge(
          "needs_attention" => { "critical" => [], "warning" => [], "total" => 0 },
          "threshold_recommendations" => []
        )
        _, data = call(StubClient.new(response))

        assert_equal "Week starting 2026-06-08T00:00:00Z: 0 critical, 0 warning.", data["summary"]
        assert_equal [ "Nothing passed its thresholds; compare an earlier period to confirm." ], data["next_steps"]
      end

      test "an unknown period is a tool error naming the accepted values" do
        result = Tools::Insights.call(period: "year", server_context: { client: StubClient.new(INSIGHTS_RESPONSE) })

        assert_predicate result, :error?
        assert_includes result.content.first[:text], "hour, day, week, month"
      end

      test "an invalid at is a tool error" do
        result = Tools::Insights.call(at: "yesterday", server_context: { client: StubClient.new(INSIGHTS_RESPONSE) })

        assert_predicate result, :error?
      end

      test "an API error is a tool error" do
        client = Object.new
        def client.get(*)
          raise CLI::Client::ApiError, "503 Service Unavailable"
        end

        result = Tools::Insights.call(server_context: { client: client })

        assert_predicate result, :error?
      end
    end
  end
end
