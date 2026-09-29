require "test_helper"
require "rails_pulse/cli/client"
require "rails_pulse/cli/config"

module RailsPulse
  module CLI
    class ClientTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      setup do
        @config = Config.new(url: "https://example.com", token: "test-token")
        @client = Client.new(@config)
      end

      teardown do
        restore_net_http_start
      end

      test "get sends X-Rails-Pulse-Token header" do
        sent_headers = {}
        stub_http_response(200, '{"data":[],"meta":{"total":0,"limit":25,"offset":0}}') do |req|
          sent_headers = req.to_hash
        end
        @client.get("/routes")

        assert_equal [ "test-token" ], sent_headers["x-rails-pulse-token"]
      end

      test "get builds correct URI with default mount path" do
        captured_uri = nil
        stub_http_response(200, '{"data":[],"meta":{"total":0,"limit":25,"offset":0}}') do |_req, uri|
          captured_uri = uri
        end
        @client.get("/routes")

        assert_equal "/rails_pulse/api/v1/routes", captured_uri.path
      end

      test "get uses custom mount_path from config" do
        config = Config.new(url: "https://example.com", token: "test-token", mount_path: "/monitoring")
        client = Client.new(config)
        captured_uri = nil
        stub_http_response(200, '{"data":[],"meta":{"total":0,"limit":25,"offset":0}}') do |_req, uri|
          captured_uri = uri
        end
        client.get("/routes")

        assert_equal "/monitoring/api/v1/routes", captured_uri.path
      end

      test "get appends query params to URI" do
        captured_uri = nil
        stub_http_response(200, '{"data":[],"meta":{"total":0,"limit":25,"offset":0}}') do |_req, uri|
          captured_uri = uri
        end
        @client.get("/requests", { limit: 10, status: "5xx" })

        assert_match(/limit=10/, captured_uri.query)
        assert_match(/status=5xx/, captured_uri.query)
      end

      test "get returns parsed JSON response" do
        body = '{"data":[{"id":1}],"meta":{"total":1,"limit":25,"offset":0}}'
        stub_http_response(200, body)
        result = @client.get("/routes")

        assert_equal [ { "id" => 1 } ], result["data"]
        assert_equal 1, result["meta"]["total"]
      end

      test "get raises ApiError on non-2xx response" do
        stub_http_response(401, '{"error":"Unauthorized"}')
        err = assert_raises(Client::ApiError) { @client.get("/routes") }
        assert_match(/401/, err.message)
      end

      test "get relays the API's error message on a 400" do
        stub_http_response(400, '{"error":"Invalid sort. Valid values: request_count, avg_duration, error_count"}')
        err = assert_raises(Client::ApiError) { @client.get("/routes", { sort: "nope" }) }

        assert_equal "400: Invalid sort. Valid values: request_count, avg_duration, error_count", err.message
      end

      test "get falls back to the status line when the error body is not JSON" do
        stub_http_response(400, "<html>Bad Request</html>")
        err = assert_raises(Client::ApiError) { @client.get("/routes") }

        assert_equal "400", err.message
      end

      test "get raises ApiError on 500 response" do
        stub_http_response(500, "Internal Server Error")
        assert_raises(Client::ApiError) { @client.get("/routes") }
      end

      test "get turns a refused connection into an ApiError naming the host" do
        stub_http_failure(Errno::ECONNREFUSED)
        err = assert_raises(Client::ApiError) { @client.get("/routes") }

        assert_match(/could not connect to example.com:443/, err.message)
      end
    end
  end
end
