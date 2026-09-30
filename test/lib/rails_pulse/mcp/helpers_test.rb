require "test_helper"
require "rails_pulse/mcp/server"

module RailsPulse
  module Mcp
    class HelpersTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      class Host
        extend Tools::Helpers
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

      # Time.parse is lenient: "last_30_days" reads as the 30th of this month
      # and "24h" as midnight, both silently wrong windows that return
      # nothing and look like "no data".
      test "resolve_window rejects a period it does not know rather than guessing" do
        %w[last_30_days last_2_hours 24h].each do |period|
          error = assert_raises(Tools::Helpers::WindowError) { Host.resolve_window(period: period) }

          assert_includes error.message, "Unknown period"
          assert_includes error.message, "last_7_days"
        end
      end

      test "resolve_window rejects a named zone rather than reading it as UTC" do
        error = assert_raises(Tools::Helpers::WindowError) { Host.resolve_window(since: "2026-09-24T12:00:00 PST") }

        assert_includes error.message, "Invalid since"
      end

      test "resolve_window accepts a bare date as midnight UTC" do
        assert_equal "2026-09-24T00:00:00Z", Host.resolve_window(since: "2026-09-24")[:since]
      end

      test "resolve_window rejects a start in the future" do
        error = assert_raises(Tools::Helpers::WindowError) do
          Host.resolve_window(since: (Time.now.utc + 86_400).strftime("%Y-%m-%dT%H:%M:%SZ"))
        end

        assert_includes error.message, "in the future"
      end

      test "fetch_all pages until the total is reached" do
        client = Object.new
        offsets = []
        client.define_singleton_method(:get) do |_path, params|
          offsets << params[:offset]
          rows = params[:offset] < 4 ? [ { "n" => params[:offset] }, { "n" => params[:offset] + 1 } ] : []
          { "data" => rows, "meta" => { "total" => 5 } }
        end
        rows, = Host.fetch_all(client, "/jobs", {}, page_size: 2)

        assert_equal [ 0, 2, 4 ], offsets
        assert_equal 4, rows.size
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
