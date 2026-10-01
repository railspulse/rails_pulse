require_relative "base_command"
require_relative "formatter"

module RailsPulse
  module CLI
    class Coverage < BaseCommand
      desc "show", "Report what has been recorded, how recently, and any gaps"
      long_desc <<~DESC
        Answers whether the data is there, rather than a question about the data: which
        application and environment answered, the span of requests, job runs and exceptions
        held, how far summaries have been generated, what retention keeps, and whether the
        background writer has dropped anything.

        Read this before concluding that nothing went wrong. An empty error list means
        "nothing recorded", which is only the same as "nothing happened" when collection was
        healthy over the window in question.

        Use --json for the full structure.
      DESC
      option :json, type: :boolean, default: false, desc: "Output raw JSON"
      def show
        with_error_handling do
          data = client.get("/coverage", {})
          capabilities = client.get("/capabilities", {})
          next say(JSON.pretty_generate(data.merge("capabilities" => capabilities))) if options[:json]

          print_installation(capabilities)
          print_telemetry(data["telemetry"] || {})
          print_summaries(data["summaries"] || {})
          print_retention(data["retention"] || {})
          print_collection(data["collection"] || {})
        end
      end

      private

      def print_installation(capabilities)
        say "Installation"
        say "  application  #{capabilities['application'] || '—'} (#{capabilities['environment']})"
        say "  version      #{capabilities['rails_pulse_version']}"
        say ""
      end

      def print_telemetry(telemetry)
        say "Telemetry"
        telemetry.each do |kind, info|
          if info["tracked"] == false
            say "  #{kind.ljust(12)} not tracked — #{info['reason']}"
          elsif info["newest"]
            say "  #{kind.ljust(12)} #{info['count']} rows, #{info['oldest']} → #{info['newest']}"
          else
            say "  #{kind.ljust(12)} nothing recorded"
          end
        end
      end

      def print_summaries(summaries)
        say ""
        say "Summaries"
        say "  hourly       #{summaries['hourly_from'] || '—'} → #{summaries['hourly_through'] || '—'}#{summaries['stale'] ? ' (stale)' : ''}"
        say "  #{summaries['note']}" if summaries["note"]
      end

      def print_retention(retention)
        say ""
        say "Retention"
        say "  raw records  #{days(retention['raw_records'])}"
        say "  hourly       #{days(retention['hourly_summaries'])}"
        say "  events       #{days(retention['events'])}"
      end

      def print_collection(collection)
        say ""
        say "Collection"
        if collection["known"] == false
          say "  unknown — #{collection['reason']}"
          return
        end

        say "  writers      #{collection['live_writers']} live, queue #{collection['queue_depth']}/#{collection['queue_size']}"
        say "  dropped      #{collection['dropped_last_hour']} in the last hour"
        say "  last beat    #{collection['last_heartbeat_at'] || 'never'}"
        say "  #{collection['note']}" if collection["note"]
      end

      def days(value)
        value ? "#{value['days']} days" : "—"
      end
    end
  end
end
