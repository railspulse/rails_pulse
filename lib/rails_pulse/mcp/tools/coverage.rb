module RailsPulse
  module Mcp
    module Tools
      class Coverage < ::MCP::Tool
        extend Helpers

        tool_name "rails_pulse_coverage"
        description "What Rails Pulse has recorded and how recently: the span of requests, job runs and " \
                    "exceptions held, how far summaries have been generated, what retention keeps, and whether " \
                    "any requests were dropped. Call this before reporting that nothing went wrong, to tell " \
                    "'no failures recorded' apart from 'no data captured'."

        annotations(
          read_only_hint: true,
          destructive_hint: false,
          open_world_hint: false
        )

        input_schema(properties: {})

        def self.call(server_context:, **_options)
          respond(server_context) do |client|
            data = client.get("/coverage", {})

            {
              as_of: data["as_of"],
              telemetry: data["telemetry"],
              summaries: data["summaries"],
              retention: data["retention"],
              collection: data["collection"],
              summary: build_summary(data),
              next_steps: build_next_steps(data)
            }
          end
        end

        private_class_method def self.build_summary(data)
          requests = data.dig("telemetry", "requests") || {}
          parts = []

          parts << if requests["newest"]
            "Requests recorded #{requests['oldest']} to #{requests['newest']} (#{requests['count']} rows)."
          else
            "No requests have been recorded."
          end

          collection = data["collection"] || {}
          parts << "Collection gap suspected." if collection["gap_suspected"]
          parts << "Summaries are behind." if data.dig("summaries", "stale")
          parts.join(" ")
        end

        # An agent that reads "no errors" without these caveats will report an
        # all-clear the data does not support.
        private_class_method def self.build_next_steps(data)
          steps = []
          collection = data["collection"] || {}
          summaries = data["summaries"] || {}

          steps << collection["note"] if collection["note"]
          steps << summaries["note"] if summaries["note"]

          if (oldest = data.dig("telemetry", "requests", "oldest"))
            steps << "Questions about anything before #{oldest} cannot be answered from raw requests; " \
                     "retention has removed them. Summaries may still cover the window."
          end

          exceptions = data.dig("telemetry", "exceptions") || {}
          if exceptions["tracked"] == false
            steps << "Exceptions are not being recorded (#{exceptions['reason']}), so an empty error result says nothing about whether exceptions occurred."
          end

          steps << "Treat an empty result from another tool as 'not recorded' rather than 'did not happen' whenever a caveat above applies."
          steps
        end
      end
    end
  end
end
