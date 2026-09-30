module RailsPulse
  module Mcp
    module Tools
      class Exceptions < ::MCP::Tool
        extend Helpers

        tool_name "rails_pulse_exceptions"
        description "Exception groups captured from web requests and background jobs: one entry per exception " \
                    "class and app-code location, with its status (open, resolved, ignored), occurrence count, " \
                    "latest message, and when it first and last fired. Use this to see what is actually raising " \
                    "right now; rails_pulse_errors only knows which endpoints answered 5xx."

        annotations(
          read_only_hint: true,
          destructive_hint: false,
          open_world_hint: false
        )

        input_schema(
          properties: {
            **Helpers.window_properties("last_7_days"),
            period: {
              type: "string",
              description: "Only groups last seen in this window: 'last_hour', 'last_24_hours', 'last_7_days', " \
                           "or 'all' for no time filter. Ignored when 'since' or 'until' is given.",
              default: "last_7_days"
            },
            status: {
              type: "string",
              description: "Lifecycle filter: 'open' (default), 'resolved', 'ignored', or 'all'",
              default: "open"
            },
            search: {
              type: "string",
              description: "Substring match on the exception class or location, e.g. 'RecordNotFound' or 'app/models'"
            },
            limit: {
              type: "integer",
              description: "Maximum number of groups (1-100)",
              default: 25
            }
          }
        )

        # `period: "all"` drops the time filter; groups are otherwise limited to
        # those last seen inside the window.
        def self.call(period: "last_7_days", status: "open", search: nil, limit: 25, server_context:, **options)
          respond(server_context) do |client|
            limit = limit.to_i.clamp(1, 100)
            all_time = period.to_s == "all" && options[:since].nil? && options[:until].nil?
            window = all_time ? nil : resolve_window(period: period, since: options[:since], until_time: options[:until])

            params = { limit: limit, offset: 0 }
            params.merge!(window_params(window)) if window
            params[:status] = status unless status.to_s == "all"
            params[:search] = search if search.to_s != ""

            result = client.get("/exceptions", params)
            groups = (result["data"] || []).map { |g| format_group(g) }
            total  = result.dig("meta", "total") || groups.size

            {
              window: window || { period: "all" },
              status_filter: status,
              total_groups: total,
              groups_returned: groups.size,
              groups: groups,
              summary: build_summary(groups, total, status),
              next_steps: build_next_steps(groups)
            }
          end
        end

        private_class_method def self.format_group(group)
          {
            id: group["id"],
            exception_class: group["exception_class"],
            location: group["location"],
            message: truncate(group["message"], 300),
            status: group["status"],
            occurrence_count: group["occurrence_count"],
            first_seen_at: group["first_seen_at"],
            last_seen_at: group["last_seen_at"],
            resolved_at: group["resolved_at"]
          }
        end

        private_class_method def self.build_summary(groups, total, status)
          label = status.to_s == "all" ? "" : "#{status} "
          return "No #{label}exception groups found for this period." if groups.empty?

          occurrences = groups.sum { |g| g[:occurrence_count].to_i }
          loudest = groups.max_by { |g| g[:occurrence_count].to_i }
          parts = [ "#{total} #{label}exception group(s), #{occurrences} occurrences across the #{groups.size} returned" ]
          parts << "Most frequent: #{loudest[:exception_class]} at #{loudest[:location] || 'unknown location'} " \
                   "(#{loudest[:occurrence_count]} occurrences)"
          parts.join(". ") + "."
        end

        private_class_method def self.build_next_steps(groups)
          return [ "Nothing is raising in this window. Widen period or set status: \"all\" to see resolved and ignored groups." ] if groups.empty?

          steps = []
          latest = groups.max_by { |g| g[:last_seen_at].to_s }
          steps << "Start with #{latest[:exception_class]} at #{latest[:location] || 'unknown location'}: it fired most recently " \
                   "(#{latest[:last_seen_at]}). Read the location and message, then open the file at that frame."
          steps << "Call rails_pulse_deployments for the same period to see whether the first_seen_at of a group lines up with a release."
          steps << "Call rails_pulse_errors to see which endpoints answered 5xx as a result, and rails_pulse_jobs for failing job classes."
          steps
        end
      end
    end
  end
end
