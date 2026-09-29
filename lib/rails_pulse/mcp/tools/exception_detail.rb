module RailsPulse
  module Mcp
    module Tools
      # Named ExceptionDetail rather than Exception so nothing in this namespace
      # shadows ::Exception.
      class ExceptionDetail < ::MCP::Tool
        extend Helpers

        tool_name "rails_pulse_exception"
        description "Everything recorded about one exception group: its status and counts plus its most recent " \
                    "occurrences, each with the full backtrace, request method, URL, filtered params, environment " \
                    "and deploy SHA. Use this after rails_pulse_exceptions (or when given an id) to find the cause " \
                    "in the code; app_frames lists the backtrace frames inside the application."

        annotations(
          read_only_hint: true,
          destructive_hint: false,
          open_world_hint: false
        )

        input_schema(
          properties: {
            id: {
              type: "integer",
              description: "The exception group id, from rails_pulse_exceptions or the dashboard URL"
            },
            occurrences: {
              type: "integer",
              description: "How many of the most recent occurrences to include (1-20)",
              default: 3
            }
          },
          required: [ "id" ]
        )

        def self.call(id:, occurrences: 3, server_context:)
          respond(server_context) do |client|
            count = occurrences.to_i.clamp(1, 20)
            result = client.get("/exceptions/#{id.to_i}", { occurrences: count })
            group = result["data"] || {}
            recent = (group["occurrences"] || []).map { |o| format_occurrence(o) }
            latest = recent.first

            {
              id: group["id"],
              exception_class: group["exception_class"],
              location: group["location"],
              message: group["message"],
              status: group["status"],
              occurrence_count: group["occurrence_count"],
              first_seen_at: group["first_seen_at"],
              last_seen_at: group["last_seen_at"],
              resolved_at: group["resolved_at"],
              app_frames: latest ? latest[:app_frames] : [],
              occurrences: recent,
              summary: build_summary(group, latest),
              next_steps: build_next_steps(group, latest)
            }
          end
        end

        private_class_method def self.format_occurrence(occurrence)
          frames = Array(occurrence["backtrace"]).map { |f| format_frame(f) }
          {
            id: occurrence["id"],
            occurred_at: occurrence["occurred_at"],
            message: truncate(occurrence["message"], 500),
            request: occurrence["request_url"] ? "#{occurrence["request_method"]} #{occurrence["request_url"]}".strip : nil,
            request_params: occurrence["request_params"],
            environment: occurrence["environment"],
            deploy_sha: occurrence["deploy_sha"],
            app_frames: frames.select { |f| app_frame?(f) },
            backtrace: frames
          }
        end

        private_class_method def self.format_frame(frame)
          return { location: frame.to_s } unless frame.is_a?(Hash)

          location = [ frame["file"], frame["line"] ].compact.join(":")
          { location: location, method: frame["method"] }
        end

        private_class_method def self.app_frame?(frame)
          frame[:location].to_s.start_with?("app/", "lib/", "config/")
        end

        private_class_method def self.build_summary(group, latest)
          return "No exception group found." if group.empty?

          parts = [ "#{group["exception_class"]} at #{group["location"] || "unknown location"}: " \
                    "#{group["status"]}, #{group["occurrence_count"]} occurrence(s), last #{group["last_seen_at"]}" ]
          if latest
            parts << (latest[:request] ? "Latest was #{latest[:request]}" : "Latest came from a background job")
            top = latest[:app_frames].first
            parts << "First app frame: #{top[:location]}#{top[:method] ? " in #{top[:method]}" : ""}" if top
          end
          parts.join(". ") + "."
        end

        private_class_method def self.build_next_steps(group, latest)
          return [ "Check the id with rails_pulse_exceptions; nothing matched." ] if group.empty?

          steps = []
          top = latest && latest[:app_frames].first
          if top
            steps << "Open #{top[:location]} and read the code around it with the latest message in mind: #{truncate(group["message"], 160)}"
          else
            steps << "No application frame in the backtrace; the raise happened in a gem. Read the outermost frames to find the call site."
          end
          steps << "Compare the occurrences' request params and URLs to see what input triggers it." if latest && latest[:request]
          steps << "Call rails_pulse_deployments with period: \"#{group["first_seen_at"]}\" to see whether a release introduced it." if group["first_seen_at"]
          steps
        end
      end
    end
  end
end
