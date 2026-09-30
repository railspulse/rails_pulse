require "json"
require "time"

module RailsPulse
  module Mcp
    module Tools
      module Helpers
        PERIODS = {
          "last_hour" => 3600,
          "last_24_hours" => 86_400,
          "last_7_days" => 604_800
        }.freeze

        # Raised for a time argument a tool cannot turn into a window. Carries
        # the correction in its message, so the agent can fix the call rather
        # than retry it unchanged.
        class WindowError < ArgumentError; end

        # A trailing Z or ±HH:MM offset.
        ZONED = /(?:Z|[+-]\d{2}:?\d{2})\z/i

        # The default window when a tool is given neither a period nor bounds.
        DEFAULT_PERIOD = "last_24_hours".freeze

        # The time arguments every windowed tool accepts. Spliced into each
        # tool's input_schema so the three stay described identically.
        def self.window_properties(default_period)
          {
            period: {
              type: "string",
              description: "Relative window: 'last_hour', 'last_24_hours', 'last_7_days', or an ISO 8601 " \
                           "timestamp to measure from. Ignored when 'since' or 'until' is given.",
              default: default_period
            },
            since: {
              type: "string",
              description: "Start of the window, ISO 8601 (e.g. '2026-09-24T12:00:00Z'). Read as UTC when no " \
                           "zone is given. Use with 'until' to pin an exact window that can be compared with another."
            },
            until: {
              type: "string",
              description: "End of the window, ISO 8601. Read as UTC when no zone is given. Omit to measure up to now."
            }
          }
        end

        def resolve_since(period)
          seconds = PERIODS[period]
          seconds ? (Time.now - seconds).iso8601 : period
        end

        # Turns a tool's time arguments into explicit UTC bounds.
        #
        # `period` names a relative window and is enough for "how are things
        # right now". `since`/`until` pin an exact one, which is what makes a
        # question repeatable: the 24 hours before a deploy stay the same 24
        # hours however long afterwards they are asked about. Explicit bounds
        # win when both are given.
        #
        # @return [Hash] `:since` and `:until` as ISO 8601 UTC strings (`:until`
        #   is nil when the window runs to now), plus `:period` describing which
        #   form was used.
        def resolve_window(period: nil, since: nil, until_time: nil)
          from = resolve_start(period, since)
          to = until_time ? parse_time(until_time, "until") : nil

          if to && from >= to
            raise WindowError, "'since' (#{from.iso8601}) must be earlier than 'until' (#{to.iso8601})."
          end

          {
            since: from.iso8601,
            until: to&.iso8601,
            period: since || until_time ? "custom" : (period || DEFAULT_PERIOD)
          }
        end

        # A timestamp with no zone is read as UTC, so a window means the same
        # thing on the agent's machine as on the server.
        def parse_time(value, name)
          string = value.to_s.strip
          parsed = Time.parse(string)
          return parsed.utc if string.match?(ZONED)

          Time.utc(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.min, parsed.sec)
        rescue ArgumentError, TypeError
          raise WindowError,
            "Invalid #{name}: #{value.inspect}. Use an ISO 8601 timestamp such as 2026-09-24T12:00:00Z."
        end

        # The API's time arguments for a resolved window. `until` is omitted
        # when the window runs to now, which the API reads as no upper bound.
        def window_params(window)
          params = { since: window[:since] }
          params[:until] = window[:until] if window[:until]
          params
        end

        def resolve_start(period, since)
          return parse_time(since, "since") if since

          seconds = PERIODS[period || DEFAULT_PERIOD]
          return (Time.now.utc - seconds) if seconds

          parse_time(period, "period")
        end

        # Every row of a paginated endpoint, for a tool that ranks the rows
        # itself. Bounded so an unexpectedly large table cannot keep the tool
        # paging forever.
        #
        # @return [Array(Array<Hash>, Hash)] the rows and the first page's response
        def fetch_all(client, path, params, page_size: 500, max_pages: 20)
          rows = []
          first = nil
          max_pages.times do |page|
            result = client.get(path, params.merge(limit: page_size, offset: page * page_size))
            first ||= result
            batch = result["data"] || []
            rows.concat(batch)
            total = result.dig("meta", "total")
            break if batch.size < page_size || (total && rows.size >= total)
          end
          [ rows, first ]
        end

        def percentile(sorted, pct)
          return 0 if sorted.empty?
          k = ((pct / 100.0) * (sorted.size - 1)).ceil
          sorted[k]
        end

        def truncate(str, length)
          str = str.to_s
          str.length > length ? "#{str[0, length]}..." : str
        end

        def respond(server_context)
          payload = yield server_context[:client]
          ::MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        rescue WindowError => e
          # The call is malformed rather than the server unreachable, so the
          # message says how to correct it.
          ::MCP::Tool::Response.new([ { type: "text", text: e.message } ], error: true)
        rescue CLI::Client::ApiError => e
          ::MCP::Tool::Response.new([ { type: "text", text: "Error querying Rails Pulse: #{e.message}" } ], error: true)
        end
      end
    end
  end
end
