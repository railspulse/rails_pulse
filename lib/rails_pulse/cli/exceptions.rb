require_relative "base_command"
require_relative "formatter"
require "json"

module RailsPulse
  module CLI
    class Exceptions < BaseCommand
      COLUMNS = [
        [ "ID",        6, :id ],
        [ "Class",    36, :exception_class ],
        [ "Location", 40, :location ],
        [ "Status",    9, :status ],
        [ "Count",     6, :occurrence_count ],
        [ "Last seen", 25, :last_seen_at ]
      ].freeze

      desc "list", "List exception groups"
      long_desc <<~DESC
        Returns exception groups — one row per exception class and location — ordered by most
        recently seen first. Each row carries the group's lifecycle status (open, resolved,
        ignored), how many times it has occurred, and when it was first and last seen.

        Filter by status:
          --status open

        Search the class name or location:
          --search RecordNotFound

        Look up one group by its fingerprint, as listed with --json or by Rails Pulse Cloud:
          --fingerprint 9b2c4e7a1f3d5c8b

        Filter by when the group was last seen (ISO 8601):
          --since 2026-06-01T00:00:00Z
          --until 2026-06-01T23:59:59Z

        Sort by last_seen_at (default), first_seen_at, or occurrence_count:
          --sort occurrence_count

        Use --json to get the latest message, fingerprint, and the full response envelope.
      DESC
      option :limit,  type: :numeric, default: 25,    desc: "Max records to return (1–500)"
      option :offset, type: :numeric, default: 0,     desc: "Number of records to skip (for pagination)"
      option :since,  type: :string,                  desc: "Return groups last seen at or after this time (ISO 8601)"
      option :until,  type: :string,                  desc: "Return groups last seen at or before this time (ISO 8601)"
      option :status, type: :string,                  desc: "Filter by status (open, resolved, ignored)"
      option :search, type: :string,                  desc: "Substring match on exception class or location"
      option :fingerprint, type: :string,             desc: "Exact fingerprint of one group"
      option :sort,   type: :string,                  desc: "Sort by last_seen_at, first_seen_at, or occurrence_count"
      option :json,   type: :boolean, default: false, desc: "Output raw JSON including meta envelope"
      def list
        with_error_handling do
          params = { limit: options[:limit], offset: options[:offset] }
          params[:since]  = options[:since]  if options[:since]
          params[:until]  = options[:until]  if options[:until]
          params[:status] = options[:status] if options[:status]
          params[:search] = options[:search] if options[:search]
          params[:fingerprint] = options[:fingerprint] if options[:fingerprint]
          params[:sort]   = options[:sort]   if options[:sort]
          result = client.get("/exceptions", params)
          Formatter.render(result, json: options[:json], columns: COLUMNS)
        end
      end

      desc "show ID", "Show one exception group with its recent occurrences and backtraces"
      long_desc <<~DESC
        Prints the group's class, location, status and counts, then each of its most recent
        occurrences with request, environment, deploy SHA, filtered params, and the backtrace.

          rails-pulse exceptions show 42
          rails-pulse exceptions show 42 --occurrences 10 --json
      DESC
      option :occurrences, type: :numeric, default: 3,     desc: "Most recent occurrences to include (1–20)"
      option :json,        type: :boolean, default: false, desc: "Output raw JSON"
      def show(id)
        with_error_handling do
          result = client.get("/exceptions/#{id.to_i}", { occurrences: options[:occurrences] })
          if options[:json]
            puts JSON.pretty_generate(result)
          else
            render_group(result["data"] || {})
          end
        end
      end

      no_commands do
        def render_group(group)
          say ""
          say "#{group["exception_class"]}  ##{group["id"]}", :bold
          say "═" * 60
          say "  Location:   #{group["location"] || "—"}"
          say "  Status:     #{group["status"]}"
          say "  Count:      #{group["occurrence_count"]}"
          say "  First seen: #{group["first_seen_at"]}"
          say "  Last seen:  #{group["last_seen_at"]}"
          say "  Message:    #{group["message"]}" if group["message"]

          Array(group["occurrences"]).each_with_index do |occurrence, index|
            say ""
            say "Occurrence #{index + 1} — #{occurrence["occurred_at"]}", :bold
            say "  Request:  #{occurrence["request_method"]} #{occurrence["request_url"]}" if occurrence["request_url"]
            say "  Env:      #{occurrence["environment"]}" if occurrence["environment"]
            say "  Deploy:   #{occurrence["deploy_sha"]}" if occurrence["deploy_sha"]
            say "  Params:   #{occurrence["request_params"].to_json}" if occurrence["request_params"]
            say "  Message:  #{occurrence["message"]}" if occurrence["message"] && occurrence["message"] != group["message"]
            Array(occurrence["backtrace"]).each do |frame|
              location = frame.is_a?(Hash) ? "#{frame["file"]}:#{frame["line"]}#{frame["method"] ? " in #{frame["method"]}" : ""}" : frame.to_s
              app = location.start_with?("app/", "lib/", "config/")
              say "    #{app ? "▸" : " "} #{location}", app ? :green : nil
            end
          end
          say ""
        end
      end
    end
  end
end
