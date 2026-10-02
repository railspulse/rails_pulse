module RailsPulse
  module Mcp
    module Tools
      class Coverage < ::MCP::Tool
        extend Helpers

        tool_name "rails_pulse_coverage"
        description "Orientation for this installation: which application and environment it is, what has " \
                    "been recorded and how recently, what retention keeps, and whether any requests were " \
                    "dropped. Call this first in a session, and before reporting that nothing went wrong, " \
                    "to tell 'no failures recorded' apart from 'no data captured'."

        annotations(
          read_only_hint: true,
          destructive_hint: false,
          open_world_hint: false
        )

        input_schema(properties: {})

        def self.call(server_context:, **_options)
          respond(server_context) do |client|
            data = client.get("/coverage", {})
            capabilities = client.get("/capabilities", {})

            {
              as_of: data["as_of"],
              installation: installation(capabilities),
              telemetry: data["telemetry"],
              summaries: data["summaries"],
              retention: data["retention"],
              collection: data["collection"],
              summary: build_summary(data),
              next_steps: build_next_steps(data)
            }
          end
        end

        # Which application and environment answered, so results gathered
        # against staging are not read as production.
        private_class_method def self.installation(capabilities)
          {
            application: capabilities["application"],
            environment: capabilities["environment"],
            rails_pulse_version: capabilities["rails_pulse_version"]
          }
        end

        private_class_method def self.build_summary(data)
          requests = data.dig("telemetry", "requests") || {}
          parts = []

          parts << if requests["tracked"] == false
            "Requests are not being recorded."
          elsif requests["newest"]
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

          (data["telemetry"] || {}).each do |kind, info|
            next unless info.is_a?(Hash) && info["tracked"] == false

            label = kind.tr("_", " ").capitalize
            steps << "#{label} are not being recorded (#{info['reason']}), so an empty #{kind.tr('_', ' ')} result " \
                     "says nothing about whether any occurred."
          end

          steps << "Treat an empty result from another tool as 'not recorded' rather than 'did not happen' whenever a caveat above applies."
          steps
        end
      end
    end
  end
end
