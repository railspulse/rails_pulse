require "test_helper"
require "rails_pulse/mcp/server"

module RailsPulse
  module Mcp
    class HelpersTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      class Host
        extend Tools::Helpers
      end

      test "resolve_since maps named periods to ISO timestamps" do
        now = Time.now
        hour = Time.iso8601(Host.resolve_since("last_hour"))
        day = Time.iso8601(Host.resolve_since("last_24_hours"))
        week = Time.iso8601(Host.resolve_since("last_7_days"))

        assert_in_delta now - 3600, hour, 5
        assert_in_delta now - 86_400, day, 5
        assert_in_delta now - 604_800, week, 5
      end

      test "resolve_since passes unknown values through as timestamps" do
        assert_equal "2026-06-01T00:00:00Z", Host.resolve_since("2026-06-01T00:00:00Z")
      end

      test "percentile returns 0 for empty input and nearest rank otherwise" do
        assert_equal 0, Host.percentile([], 95)
        assert_equal 10, Host.percentile([ 10 ], 95)
        assert_equal 60, Host.percentile((10..100).step(10).to_a, 50)
        assert_equal 100, Host.percentile((10..100).step(10).to_a, 99)
      end

      test "truncate shortens long strings only" do
        assert_equal "short", Host.truncate("short", 10)
        assert_equal "abcde...", Host.truncate("abcdefghij", 5)
        assert_equal "", Host.truncate(nil, 5)
      end

      test "respond wraps the payload as pretty JSON" do
        result = Host.respond({ client: :client }) { |client| { got: client.to_s } }

        assert_not result.error?
        assert_equal({ "got" => "client" }, JSON.parse(result.content.first[:text]))
      end

      test "respond turns API errors into error responses" do
        result = Host.respond({ client: nil }) { raise CLI::Client::ApiError, "503 Service Unavailable" }

        assert_predicate result, :error?
        assert_includes result.content.first[:text], "503 Service Unavailable"
      end

      # resolve_window — relative periods

      test "resolve_window turns a named period into a start and an open end" do
        window = Host.resolve_window(period: "last_hour")

        assert_in_delta Time.now - 3600, Time.iso8601(window[:since]), 5
        assert_nil window[:until]
        assert_equal "last_hour", window[:period]
      end

      test "resolve_window falls back to the default period with no arguments" do
        window = Host.resolve_window

        assert_in_delta Time.now - 86_400, Time.iso8601(window[:since]), 5
        assert_equal "last_24_hours", window[:period]
      end

      test "resolve_window accepts a bare timestamp as the period" do
        window = Host.resolve_window(period: "2026-09-24T12:00:00Z")

        assert_equal "2026-09-24T12:00:00Z", window[:since]
      end

      # resolve_window — explicit bounds

      test "resolve_window pins both ends and reports them in UTC" do
        window = Host.resolve_window(since: "2026-09-24T12:00:00Z", until_time: "2026-09-25T12:00:00Z")

        assert_equal "2026-09-24T12:00:00Z", window[:since]
        assert_equal "2026-09-25T12:00:00Z", window[:until]
        assert_equal "custom", window[:period]
      end

      test "resolve_window converts an offset timestamp to UTC" do
        window = Host.resolve_window(since: "2026-09-24T12:00:00+10:00")

        assert_equal "2026-09-24T02:00:00Z", window[:since]
      end

      # A window must mean the same thing on the agent's machine and the
      # server, so an unzoned timestamp is not read as local time.
      test "resolve_window reads a timestamp with no zone as UTC" do
        window = Host.resolve_window(since: "2026-09-24T12:00:00")

        assert_equal "2026-09-24T12:00:00Z", window[:since]
      end

      test "resolve_window prefers explicit bounds over a period" do
        window = Host.resolve_window(period: "last_hour", since: "2026-09-24T12:00:00Z")

        assert_equal "2026-09-24T12:00:00Z", window[:since]
        assert_equal "custom", window[:period]
      end

      # Edge Cases

      test "resolve_window rejects an unparseable timestamp and names the argument" do
        error = assert_raises(Tools::Helpers::WindowError) { Host.resolve_window(since: "yesterday") }

        assert_includes error.message, "Invalid since"
        assert_includes error.message, "ISO 8601"
      end

      test "resolve_window rejects a window that ends before it starts" do
        error = assert_raises(Tools::Helpers::WindowError) do
          Host.resolve_window(since: "2026-09-25T12:00:00Z", until_time: "2026-09-24T12:00:00Z")
        end

        assert_includes error.message, "must be earlier than"
      end

      test "resolve_window rejects a zero-length window" do
        assert_raises(Tools::Helpers::WindowError) do
          Host.resolve_window(since: "2026-09-24T12:00:00Z", until_time: "2026-09-24T12:00:00Z")
        end
      end

      test "respond turns a window error into a correctable message" do
        result = Host.respond({ client: nil }) { raise Tools::Helpers::WindowError, "Invalid since: \"yesterday\"." }

        assert_predicate result, :error?
        assert_includes result.content.first[:text], "Invalid since"
      end

      # window_params

      test "window_params omits until for an open-ended window" do
        params = Host.window_params({ since: "2026-09-24T12:00:00Z", until: nil })

        assert_equal({ since: "2026-09-24T12:00:00Z" }, params)
      end

      test "window_params passes both bounds through when the window is closed" do
        params = Host.window_params({ since: "2026-09-24T12:00:00Z", until: "2026-09-25T12:00:00Z" })

        assert_equal "2026-09-25T12:00:00Z", params[:until]
      end
    end
  end
end
