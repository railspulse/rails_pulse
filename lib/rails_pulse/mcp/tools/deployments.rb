module RailsPulse
  module Mcp
    module Tools
      class Deployments < ::MCP::Tool
        extend Helpers

        tool_name "rails_pulse_deployments"
        description "Recent deployments with revision, start and finish time, metadata, and whether each one made " \
                    "the application slower or more error-prone. Each deployment's `comparison` sets the hour " \
                    "before the hour it started in against the hour after: `degraded` when average or p95 " \
                    "response time is more than 1.5x worse or the error rate more than 1.25x worse, " \
                    "`insufficient_data` under 10 requests in either hour, `pending` until the hour after has " \
                    "been summarized. Use it to pin an investigation to a release."

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
            metadata: deployment["metadata"],
            comparison: deployment["comparison"]
          }
        end

        private_class_method def self.build_summary(deployments)
          return "No deployments recorded in this period." if deployments.empty?

          latest = deployments.first
          state = latest[:in_progress] ? " (in progress)" : ""
          summary = "#{deployments.size} deployment(s). Latest: #{latest[:short_revision]} at #{latest[:started_at]}#{state}."

          degraded = deployments.select { |d| outcome(d) == "degraded" }
          return summary if degraded.empty?

          "#{summary} Degraded: #{degraded.map { |d| "#{d[:short_revision]} (#{degraded_metrics(d).join(', ')})" }.join('; ')}."
        end

        private_class_method def self.build_next_steps(deployments)
          if deployments.empty?
            return [ "Record deployments via `rails_pulse:record_deployment` or POST /deployments so an investigation can be pinned to a release." ]
          end

          target = deployments.find { |d| outcome(d) == "degraded" } || deployments.first
          before = target.dig(:comparison, "before")
          after = target.dig(:comparison, "after")
          unless before && after
            return [ "Call rails_pulse_slow_requests and rails_pulse_errors with since: \"#{target[:started_at]}\" " \
                     "and compare against the same length of time before it." ]
          end

          [
            "To see what #{target[:short_revision]} changed, call rails_pulse_slow_requests and rails_pulse_errors " \
            "with since: \"#{after['from']}\", until: \"#{after['to']}\", then with since: \"#{before['from']}\", " \
            "until: \"#{before['to']}\", and compare the two."
          ]
        end

        private_class_method def self.outcome(deployment)
          deployment.dig(:comparison, "outcome")
        end

        private_class_method def self.degraded_metrics(deployment)
          (deployment.dig(:comparison, "metrics") || []).select { |m| m["outcome"] == "degraded" }.map { |m| m["metric"] }
        end
      end
    end
  end
end
