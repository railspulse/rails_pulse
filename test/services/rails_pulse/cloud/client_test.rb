require "test_helper"

module RailsPulse
  module Cloud
    class ClientTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      setup do
        @settings = Configuration::CloudSettings.new
        @settings.api_key = "rpc_4f9Kx2mQ8vTzL1nB7wYc3HdR6sJe5PaU"
        @settings.application = "shop"
      end

      # Structure Tests

      test "posts gzipped JSON with the key, contract version and user agent" do
        captured = nil
        stub_http_response(202, "{}") { |request, uri| captured = [ request, uri ] }

        response = Client.new(@settings).post({ contract: 1 }.to_json)
        request, uri = captured

        assert_equal 202, response.status
        assert_equal "https://ingest.railspulse.com/v1/batches", uri.to_s
        assert_equal "Bearer rpc_4f9Kx2mQ8vTzL1nB7wYc3HdR6sJe5PaU", request["Authorization"]
        assert_equal "gzip", request["Content-Encoding"]
        assert_equal "1", request["Rails-Pulse-Contract"]
        assert_match %r{\Arails_pulse/#{Regexp.escape(RailsPulse::VERSION)} \(ruby .+; rails .+\)\z}, request["User-Agent"]
        assert_equal({ "contract" => 1 }, JSON.parse(Zlib.gunzip(request.body)))
      end

      test "keeps a path on the configured URL, as staging uses" do
        @settings.url = "https://staging.railspulse.com/ingest/"
        captured = nil
        stub_http_response(202, "{}") { |_request, uri| captured = uri }

        Client.new(@settings).post("{}")

        assert_equal "https://staging.railspulse.com/ingest/v1/batches", captured.to_s
      end

      test "an error body is read for its message" do
        stub_http_response(401, { code: "invalid_api_key", message: "That key has been revoked." }.to_json)

        response = Client.new(@settings).post("{}")

        assert_equal "invalid_api_key", response.error["code"]
        assert_equal "That key has been revoked.", response.message
      end

      # Edge Cases

      test "a timeout or refused connection is raised as Unavailable" do
        silence_warnings { Net::HTTP.define_singleton_method(:start) { |*, **| raise Net::OpenTimeout, "execution expired" } }

        error = assert_raises(Client::Unavailable) { Client.new(@settings).post("{}") }
        assert_includes error.message, "Net::OpenTimeout"
      end

      test "a body that is not JSON gives the status as the message" do
        stub_http_response(503, "<html>down</html>")

        assert_equal "HTTP 503", Client.new(@settings).post("{}").message
      end
    end
  end
end
