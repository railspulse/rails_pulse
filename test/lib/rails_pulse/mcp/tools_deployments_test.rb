require "test_helper"
require "rails_pulse/mcp/server"

module RailsPulse
  module Mcp
    class ToolsDeploymentsTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      class StubClient
        attr_reader :calls

        def initialize(responses = {})
          @responses = responses
          @calls = []
        end

        def get(path, params = {})
          @calls << [ path, params ]
          @responses[path] || { "data" => [], "meta" => { "total" => 0, "limit" => 25, "offset" => 0 } }
        end
      end

      DEPLOYMENTS_RESPONSE = {
        "data" => [
          { "id" => 3, "revision" => "ccc333", "short_revision" => "ccc333", "started_at" => "2026-06-03T09:00:00Z", "finished_at" => nil,
            "duration_seconds" => nil, "in_progress" => true, "metadata" => {} },
          { "id" => 2, "revision" => "bbb222", "short_revision" => "bbb222", "started_at" => "2026-06-02T09:00:00Z", "finished_at" => "2026-06-02T09:01:00Z",
            "duration_seconds" => 60.0, "in_progress" => false, "metadata" => { "branch" => "main" } },
          { "id" => 1, "revision" => "aaa111", "short_revision" => "aaa111", "started_at" => "2026-06-01T09:00:00Z", "finished_at" => "2026-06-01T09:01:00Z",
            "duration_seconds" => 60.0, "in_progress" => false, "metadata" => {} }
        ],
        "meta" => { "total" => 3, "limit" => 10, "offset" => 0 }
      }.freeze

      COMPARED_RESPONSE = {
        "data" => [
          DEPLOYMENTS_RESPONSE["data"][0].merge("comparison" => {
            "outcome" => "pending", "before" => { "from" => "2026-06-03T08:00:00Z", "to" => "2026-06-03T09:00:00Z", "requests" => 40 },
            "after" => { "from" => "2026-06-03T10:00:00Z", "to" => "2026-06-03T11:00:00Z", "requests" => 0 }, "metrics" => []
          }),
          DEPLOYMENTS_RESPONSE["data"][1].merge("comparison" => {
            "outcome" => "degraded", "before" => { "from" => "2026-06-02T08:00:00Z", "to" => "2026-06-02T09:00:00Z", "requests" => 40 },
            "after" => { "from" => "2026-06-02T10:00:00Z", "to" => "2026-06-02T11:00:00Z", "requests" => 38 },
            "metrics" => [
              { "metric" => "avg_response_time", "outcome" => "clean" },
              { "metric" => "p95_response_time", "outcome" => "degraded" },
              { "metric" => "error_rate", "outcome" => "degraded" }
            ]
          })
        ],
        "meta" => { "total" => 2, "limit" => 10, "offset" => 0 }
      }.freeze

      def client(responses = {})
        StubClient.new(responses)
      end

      def call(tool, client, **args)
        result = tool.call(**args, server_context: { client: client })
        [ result, JSON.parse(result.content.first[:text]) ]
      end

      def error_client
        Object.new.tap do |c|
          def c.get(*, **)
            raise CLI::Client::ApiError, "503 Service Unavailable"
          end
        end
      end

      # --- Deployments ---

      test "deployments lists each deploy with its timing and metadata" do
        c = client("/deployments" => DEPLOYMENTS_RESPONSE)
        _, data = call(Tools::Deployments, c, limit: 1000)

        assert_equal 100, c.calls.first[1][:limit]
        assert_equal 3, data["total_deployments"]
        assert_equal %w[ccc333 bbb222 aaa111], data["deployments"].map { |d| d["short_revision"] }
        assert data["deployments"].first["in_progress"]
        assert_in_delta 60.0, data["deployments"][1]["duration_seconds"]
        assert_equal({ "branch" => "main" }, data["deployments"][1]["metadata"])
        assert_equal "3 deployment(s). Latest: ccc333 at 2026-06-03T09:00:00Z (in progress).", data["summary"]
      end

      test "deployments summary omits the in-progress note for a finished deploy" do
        finished = DEPLOYMENTS_RESPONSE.merge("data" => DEPLOYMENTS_RESPONSE["data"].last(2))
        _, data = call(Tools::Deployments, client("/deployments" => finished))

        assert_equal "2 deployment(s). Latest: bbb222 at 2026-06-02T09:00:00Z.", data["summary"]
      end

      test "deployments next_steps point at the latest deploy time when nothing was compared" do
        _, data = call(Tools::Deployments, client("/deployments" => DEPLOYMENTS_RESPONSE))

        assert_equal 1, data["next_steps"].size
        assert_includes data["next_steps"].first, 'since: "2026-06-03T09:00:00Z"'
        assert_includes data["next_steps"].first, "rails_pulse_slow_requests"
      end

      test "deployments pass each deployment's comparison through" do
        _, data = call(Tools::Deployments, client("/deployments" => COMPARED_RESPONSE))

        assert_equal "pending", data["deployments"].first["comparison"]["outcome"]
        assert_equal "degraded", data["deployments"][1]["comparison"]["outcome"]
      end

      test "deployments summary names the degraded deployments and metrics" do
        _, data = call(Tools::Deployments, client("/deployments" => COMPARED_RESPONSE))

        assert_equal "2 deployment(s). Latest: ccc333 at 2026-06-03T09:00:00Z (in progress). " \
                     "Degraded: bbb222 (p95_response_time, error_rate).", data["summary"]
      end

      test "deployments next_steps skip a pending deployment for one that was compared" do
        clean = COMPARED_RESPONSE["data"][1].merge("comparison" => COMPARED_RESPONSE["data"][1]["comparison"].merge("outcome" => "clean"))
        response = COMPARED_RESPONSE.merge("data" => [ COMPARED_RESPONSE["data"][0], clean ])
        _, data = call(Tools::Deployments, client("/deployments" => response))

        assert_includes data["next_steps"].first, "bbb222"
      end

      test "deployments next_steps fall back to since when only a pending deployment is listed" do
        response = COMPARED_RESPONSE.merge("data" => [ COMPARED_RESPONSE["data"][0] ])
        _, data = call(Tools::Deployments, client("/deployments" => response))

        assert_includes data["next_steps"].first, 'since: "2026-06-03T09:00:00Z"'
      end

      test "deployments next_steps compare the hours either side of a degraded deployment" do
        _, data = call(Tools::Deployments, client("/deployments" => COMPARED_RESPONSE))
        step = data["next_steps"].first

        assert_includes step, "bbb222"
        assert_includes step, 'since: "2026-06-02T10:00:00Z", until: "2026-06-02T11:00:00Z"'
        assert_includes step, 'since: "2026-06-02T08:00:00Z", until: "2026-06-02T09:00:00Z"'
      end

      test "deployments explains how to record deployments when none exist" do
        _, data = call(Tools::Deployments, client)

        assert_includes data["summary"], "No deployments"
        assert_includes data["next_steps"].first, "record_deployment"
      end

      test "deployments handles API error" do
        result = Tools::Deployments.call(server_context: { client: error_client })

        assert_predicate result, :error?
      end
    end
  end
end
