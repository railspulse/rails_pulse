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

        def resolve_since(period)
          seconds = PERIODS[period]
          seconds ? (Time.now - seconds).iso8601 : period
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
        rescue CLI::Client::ApiError => e
          ::MCP::Tool::Response.new([ { type: "text", text: "Error querying Rails Pulse: #{e.message}" } ], error: true)
        end
      end
    end
  end
end
