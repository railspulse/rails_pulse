module RailsPulse
  module Mcp
    module Tools
      class Deployments < ::MCP::Tool
        extend Helpers

        tool_name "rails_pulse_deployments"
        description "Recent deployments with revision, start and finish time, and metadata. Use this to pin an " \
                    "investigation to a deploy time, then compare the other tools before and after it to see " \
                    "whether a release made things worse."

        annotations(
          read_only_hint: true,
          destructive_hint: false,
          open_world_hint: false
        )

        input_schema(
          properties: {
            **Helpers.window_properties("last_7_days"),
            limit: {
              type: "integer",
              description: "Maximum number of deployments (1-100)",
              default: 10
            }
          }
        )

        def self.call(period: "last_7_days", limit: 10, server_context:, **options)
          respond(server_context) do |client|
            window = resolve_window(period: period, since: options[:since], until_time: options[:until])
            limit = limit.to_i.clamp(1, 100)
            result = client.get("/deployments", window_params(window).merge(limit: limit))
            deployments = (result["data"] || []).map { |d| format_deployment(d) }

            {
              window: window,
              total_deployments: result.dig("meta", "total") || deployments.size,
              deployments: deployments,
              summary: build_summary(deployments),
              next_steps: build_next_steps(deployments)
            }
          end
        end

        private_class_method def self.format_deployment(deployment)
          {
            revision: deployment["revision"],
            short_revision: deployment["short_revision"],
            started_at: deployment["started_at"],
            finished_at: deployment["finished_at"],
            duration_seconds: deployment["duration_seconds"],
            in_progress: deployment["in_progress"] == true,
            metadata: deployment["metadata"]
          }
        end

        private_class_method def self.build_summary(deployments)
          return "No deployments recorded in this period." if deployments.empty?

          latest = deployments.first
          state = latest[:in_progress] ? " (in progress)" : ""
          "#{deployments.size} deployment(s). Latest: #{latest[:short_revision]} at #{latest[:started_at]}#{state}."
        end

        private_class_method def self.build_next_steps(deployments)
          if deployments.empty?
            return [ "Record deployments via `rails_pulse:record_deployment` or POST /deployments so an investigation can be pinned to a release." ]
          end

          latest = deployments.first
          [
            "To see what #{latest[:short_revision]} changed, call rails_pulse_slow_requests and rails_pulse_errors " \
            "with period: \"#{latest[:started_at]}\" and compare against the period before it."
          ]
        end
      end
    end
  end
end
