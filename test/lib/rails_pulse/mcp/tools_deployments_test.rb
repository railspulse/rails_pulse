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

      test "deployments next_steps point at the latest deploy time" do
        _, data = call(Tools::Deployments, client("/deployments" => DEPLOYMENTS_RESPONSE))

        assert_equal 1, data["next_steps"].size
        assert_includes data["next_steps"].first, "ccc333"
        assert_includes data["next_steps"].first, 'period: "2026-06-03T09:00:00Z"'
        assert_includes data["next_steps"].first, "rails_pulse_slow_requests"
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
