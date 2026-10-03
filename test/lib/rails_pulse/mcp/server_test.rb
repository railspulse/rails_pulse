require "test_helper"
require "rails_pulse/mcp/server"

module RailsPulse
  module Mcp
    class ServerTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      setup do
        ENV["RAILS_PULSE_URL"]   = "https://example.com"
        ENV["RAILS_PULSE_TOKEN"] = "test-token"
      end

      teardown do
        ENV.delete("RAILS_PULSE_URL")
        ENV.delete("RAILS_PULSE_TOKEN")
      end

      test "build_server returns an MCP::Server" do
        server = Server.build_server

        assert_kind_of ::MCP::Server, server
      end

      test "server has correct name and version" do
        server = Server.build_server

        assert_equal "rails_pulse", server.name
        assert_equal RailsPulse::VERSION, server.version
      end

      test "server registers all eleven expected tools" do
        server = Server.build_server
        tool_names = server.tools.keys.sort

        assert_equal %w[
          rails_pulse_coverage
          rails_pulse_deployments
          rails_pulse_endpoint
          rails_pulse_errors
          rails_pulse_exception
          rails_pulse_exceptions
          rails_pulse_insights
          rails_pulse_jobs
          rails_pulse_queries
          rails_pulse_routes
          rails_pulse_slow_requests
        ], tool_names
      end

      test "all tools are read-only" do
        server = Server.build_server

        server.tools.each_value do |tool|
          assert tool.annotations.read_only_hint,
                 "Expected #{tool.tool_name} to have read_only_hint: true"
        end
      end

      test "all tools have descriptions" do
        server = Server.build_server

        server.tools.each_value do |tool|
          assert_predicate tool.description, :present?,
                 "Expected #{tool.tool_name} to have a description"
        end
      end

      test "server passes client through server_context" do
        config = CLI::Config.new(url: "https://example.com", token: "tok")
        client = CLI::Client.new(config)
        server = Server.build_server(client: client)

        assert_equal client, server.instance_variable_get(:@server_context)[:client]
      end

      test "tools list matches Server.tools" do
        expected = Server.tools.map(&:tool_name).sort
        server = Server.build_server
        actual = server.tools.keys.sort

        assert_equal expected, actual
      end

      # Through the server rather than Tool.call, so the mcp gem's input
      # validation and argument handling run as they do for a real agent.

      def call_tool(name, arguments, client: StubClient.new)
        server = Server.build_server(client: client)
        request = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }
        JSON.parse(server.handle_json(request.to_json))
      end

      class StubClient
        attr_reader :calls

        def initialize
          @calls = []
        end

        def get(path, params = {})
          @calls << [ path, params ]
          # A show endpoint answers one object rather than a list.
          return { "data" => { "id" => 1, "occurrences" => [] } } if path.start_with?("/exceptions/")

          { "data" => [], "meta" => { "total" => 0 } }
        end
      end

      test "rails_pulse_queries accepts the integer route_id other tools return" do
        client = StubClient.new
        response = call_tool("rails_pulse_queries", { route: 42 }, client: client)

        assert_nil response["error"]
        assert_not response.dig("result", "isError")
        assert_equal 42, client.calls.first[1][:route]
      end

      test "rails_pulse_exceptions accepts since and until" do
        response = call_tool("rails_pulse_exceptions", { since: "2026-09-24T12:00:00Z", until: "2026-09-25T12:00:00Z" })

        assert_nil response["error"]
        assert_not response.dig("result", "isError")
      end

      test "every tool tolerates an argument it does not declare" do
        required = { "rails_pulse_endpoint" => { endpoint: "/checkout" }, "rails_pulse_exception" => { id: 1 } }

        Server.tools.map(&:tool_name).each do |name|
          response = call_tool(name, required.fetch(name, {}).merge(unexpected: true))

          assert_nil response["error"], "#{name} failed with #{response['error'].inspect}"
        end
      end

      test "build_server fails without credentials" do
        ENV.delete("RAILS_PULSE_URL")
        ENV.delete("RAILS_PULSE_TOKEN")

        assert_raises(CLI::Config::ConfigError) { Server.build_server }
      end
    end
  end
end
