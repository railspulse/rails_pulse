require "json"

module RailsPulse
  module Mcp
    module Tools
      class Errors < ::MCP::Tool
        extend Helpers

        tool_name "rails_pulse_errors"
        description "Show recent errors: HTTP 4xx/5xx responses grouped by endpoint. " \
                    "Use this to identify which endpoints are failing and how often."

        annotations(
          read_only_hint: true,
          destructive_hint: false,
          open_world_hint: false
        )

        input_schema(
          properties: {
            **Helpers.window_properties("last_24_hours"),
            limit: {
              type: "integer",
              description: "Maximum number of error requests to fetch (1-500)",
              default: 100
            },
            status: {
              type: "string",
              description: "Error class filter: '4xx', '5xx' (default), or exact code like '500'",
              default: "5xx"
            }
          }
        )

        def self.call(period: "last_24_hours", limit: 100, status: "5xx", server_context:, **options)
          respond(server_context) do |client|
            window = resolve_window(period: period, since: options[:since], until_time: options[:until])
            limit = limit.to_i.clamp(1, 500)

            params = { limit: limit, offset: 0 }
            params.merge!(window_params(window))
            params[:status] = status

            result = client.get("/requests", params)
            requests = result["data"] || []
            total = result.dig("meta", "total") || requests.size

            by_endpoint = requests.group_by { |r| r["controller_action"] || "unknown" }

            error_groups = by_endpoint.map do |action, reqs|
              sorted = reqs.sort_by { |r| r["occurred_at"].to_s }.reverse
              statuses = reqs.map { |r| r["status"] }.tally.sort_by { |_, c| -c }

              {
                endpoint: action,
                count: reqs.size,
                status_codes: statuses.map { |code, count| { status: code, count: count } },
                first_seen: sorted.last&.dig("occurred_at"),
                last_seen: sorted.first&.dig("occurred_at"),
                avg_duration_ms: (reqs.sum { |r| r["duration"].to_f } / reqs.size).round(1)
              }
            end

            error_groups.sort_by! { |g| -g[:count] }

            {
              window: window,
              status_filter: status,
              total_errors: total,
              errors_returned: requests.size,
              by_endpoint: error_groups,
              summary: build_summary(error_groups, total, status)
            }
          end
        end

        private_class_method def self.build_summary(groups, total, status)
          return "No #{status} errors found for this period." if groups.empty?

          worst = groups.first
          parts = [ "#{total} total #{status} errors across #{groups.size} endpoint(s)" ]
          parts << "Most errors: #{worst[:endpoint]} (#{worst[:count]} occurrences)"

          parts.join(". ") + "."
        end
      end
    end
  end
end
