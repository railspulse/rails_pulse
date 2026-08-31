module RailsPulse
  module Exceptions
    # Builds the plain-text "Raw Data" block shown on the exception pages and
    # copied to the clipboard for pasting into an LLM.
    #
    # Markdown rather than JSON (as the query page uses) because the payload is
    # mostly backtrace and source snippets, which JSON string-escapes into
    # something neither a human nor a model reads well.
    #
    # Runs its own aggregate queries off the group's occurrences association so
    # the views and controllers stay thin and this stays independently testable.
    class RawData
      include RailsPulse::BacktraceHelper

      # Caps keep the payload pasteable.
      MAX_EXPANDED_FRAMES = 10
      MAX_ENDPOINTS = 10
      MAX_FRAMES = 50
      SOURCE_RADIUS = 3
      RECENT_WINDOW = 24.hours
      PRIOR_WINDOW = 7.days

      def initialize(group, occurrence: nil, aggregates: true)
        @group = group
        @occurrence = occurrence
        @aggregates = aggregates
      end

      def to_s
        sections.compact_blank.join("\n\n") << "\n"
      end

      private

      attr_reader :group, :occurrence

      def sections
        [
          heading,
          summary_section,
          frequency_section,
          deploy_section,
          request_section,
          params_section,
          backtrace_section,
          source_section
        ]
      end

      def aggregates?
        @aggregates
      end

      def heading
        "# Exception: #{group.exception_class}"
      end

      def summary_section
        list = [
          [ "Class", group.exception_class ],
          [ "Message", message ],
          [ "Location", group.location.presence || "unknown" ],
          [ "Status", group.status ],
          [ "Preserved from cleanup", group.preserve? ? "yes" : "no" ],
          [ "Fingerprint", group.fingerprint ]
        ]

        section("Summary", bullets(list))
      end

      # The group message is sanitized at capture; occurrence messages are too
      # (see ExceptionMessageSanitizer), but fall back to the group's if blank.
      def message
        (occurrence&.message.presence || group.message.presence || "—")
      end

      def frequency_section
        list = [
          [ "First seen", timestamp(group.first_seen_at) ],
          [ "Last seen", timestamp(group.last_seen_at) ],
          [ "Total occurrences (lifetime)", group.occurrence_count ]
        ]

        if aggregates?
          list << [ "Stored occurrences", "#{stored_count} (older rows may have been pruned by retention)" ]
          list << [ "Last 24 hours", recent_count ]
          list << [ "Preceding 7 days", prior_count ]
        end

        section("Frequency", bullets(list))
      end

      def deploy_section
        return unless aggregates?

        shas = occurrences.where.not(deploy_sha: nil).distinct.pluck(:deploy_sha)
        return if shas.empty?

        first_sha = occurrences.order(:occurred_at).pick(:deploy_sha)

        list = [ [ "Deploy SHAs seen", shas.join(", ") ] ]
        list << [ "Earliest stored occurrence deployed at", first_sha ] if first_sha.present?

        section("Deploys", bullets(list))
      end

      def request_section
        lines = []

        if aggregates?
          environments = occurrences.where.not(environment: nil).distinct.pluck(:environment)
          lines << "- Environments: #{environments.join(', ')}" if environments.any?

          endpoints = occurrences.where.not(request_url: nil)
                                 .distinct.limit(MAX_ENDPOINTS)
                                 .pluck(:request_method, :request_url)
          if endpoints.any?
            lines << "- Endpoints:"
            endpoints.each { |method, url| lines << "  - #{method.presence || '?'} #{url}" }
          end
        elsif occurrence
          lines << "- Environment: #{occurrence.environment}" if occurrence.environment.present?
          if occurrence.request_url.present?
            lines << "- Endpoint: #{occurrence.request_method.presence || '?'} #{occurrence.request_url}"
          end
          lines << "- Deploy SHA: #{occurrence.deploy_sha}" if occurrence.deploy_sha.present?
          lines << "- Occurred at: #{timestamp(occurrence.occurred_at)}"
        end

        section("Request context", lines.join("\n")) if lines.any?
      end

      # Already run through ActiveSupport::ParameterFilter at capture time.
      def params_section
        params = occurrence&.request_params
        return if params.blank?

        section("Request params (filtered)", fenced(JSON.pretty_generate(params), "json"))
      end

      def backtrace_section
        return if frames.empty?

        lines = frames.each_with_index.map do |frame, index|
          origin = app_frame?(frame) ? "app" : "gem"
          "#{(index + 1).to_s.rjust(2)}. [#{origin}] #{frame_display_path(frame)}:#{frame['line']}:in `#{frame['method']}'"
        end

        title = "Backtrace"
        title += " (occurrence at #{timestamp(occurrence.occurred_at)})" if occurrence&.occurred_at

        section(title, fenced(lines.join("\n")))
      end

      # Source is read from disk for app frames only, and BacktraceHelper
      # sandboxes reads to Rails.root.
      def source_section
        expanded = frames.select { |frame| app_frame?(frame) }
                         .first(MAX_EXPANDED_FRAMES)
                         .filter_map do |frame|
          lines = frame_source_lines(frame, radius: SOURCE_RADIUS)
          next if lines.blank?

          body = lines.map do |lineno, content|
            marker = lineno == frame["line"].to_i ? ">" : " "
            "#{marker} #{lineno.to_s.rjust(4)} | #{content}"
          end.join("\n")

          "### #{frame_display_path(frame)}:#{frame['line']} — `#{frame['method']}`\n\n#{fenced(body, 'ruby')}"
        end

        return if expanded.empty?

        section("Source", expanded.join("\n\n"))
      end

      def frames
        @frames ||= Array(occurrence&.backtrace).first(MAX_FRAMES).select { |frame| frame.is_a?(Hash) }
      end

      def occurrences
        group.occurrences
      end

      def stored_count
        @stored_count ||= occurrences.count
      end

      def recent_count
        @recent_count ||= occurrences.where(occurred_at: RECENT_WINDOW.ago..).count
      end

      def prior_count
        @prior_count ||= occurrences.where(occurred_at: (RECENT_WINDOW + PRIOR_WINDOW).ago...RECENT_WINDOW.ago).count
      end

      def timestamp(time)
        return "—" if time.blank?
        time.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
      end

      def bullets(pairs)
        pairs.map { |label, value| "- #{label}: #{value}" }.join("\n")
      end

      def fenced(body, language = "")
        "```#{language}\n#{body}\n```"
      end

      def section(title, body)
        return if body.blank?
        "## #{title}\n\n#{body}"
      end
    end
  end
end
