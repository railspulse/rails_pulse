module RailsPulse
  module Dashboard
    # The dashboard's one-line answer to "is anything wrong?", built from the
    # per-area HealthSummary and the NeedsAttention list the page has already
    # loaded. It runs no queries of its own. The worst state anywhere sets the
    # overall state, so a single critical area turns the whole panel red.
    class Verdict
      STATUS_LABELS = { ok: "Operational", warning: "Degraded", critical: "Action needed" }.freeze

      # Above this many separately named problems the headline would run to
      # several lines, so it counts them by severity instead.
      MAX_NAMED_PROBLEMS = 2

      Area = Struct.new(
        :key, :name, :state, :url, :description, :labels, :count, :label, :detail, :meter,
        keyword_init: true
      )

      Action = Struct.new(:label, :url, :icon, keyword_init: true)

      attr_reader :areas, :state

      def initialize(health_summary:, needs_attention:, range_label:)
        @health          = health_summary
        @needs_attention = needs_attention
        @range_label     = range_label
        @areas           = build_areas
        @state           = overall_state
      end

      def status_label
        STATUS_LABELS.fetch(state)
      end

      def title
        return "All systems operational" if state == :ok

        if problems.any? && problems.size <= MAX_NAMED_PROBLEMS
          problems.to_sentence.upcase_first
        elsif attention_total > 0
          [
            ("#{critical_total} critical" if critical_total > 0),
            ("#{warning_total} #{"warning".pluralize(warning_total)}" if warning_total > 0)
          ].compact.to_sentence
        else
          "#{troubled_areas.size} #{"area".pluralize(troubled_areas.size)} need attention"
        end
      end

      def summary
        return "Nothing is slow, failing or firing." if state == :ok

        healthy = healthy_sentence
        if problems.size > MAX_NAMED_PROBLEMS
          [ "Across #{troubled_areas.map { |area| area.name.downcase }.to_sentence}.", healthy ].compact.join(" ")
        else
          healthy || "Every area needs a look."
        end
      end

      # Where to go first: the attention list when it has entries, otherwise
      # the worst area that has a page of its own.
      def action
        if attention_total > 0
          Action.new(label: "Review #{attention_total} #{"issue".pluralize(attention_total)}", url: "#needs-attention", icon: "↓")
        elsif (area = worst_linked_area)
          Action.new(label: "Open #{area.name.downcase}", url: area.url, icon: "→")
        end
      end

      private

      def url_helpers
        RailsPulse::Engine.routes.url_helpers
      end

      def exception_thresholds
        RailsPulse.configuration.exception_thresholds
      end

      # Each area's labels for its three counts. Tracking and Storage only
      # appear when they are under pressure.
      def area_definitions
        [
          { key: :routes, name: "Routes", url: -> { url_helpers.routes_path } },
          { key: :queries, name: "Queries", url: -> { url_helpers.queries_path } },
          { key: :jobs, name: "Jobs", url: -> { url_helpers.jobs_path }, critical_label: "failing" },
          # Exceptions have no "slow" state: a group that fired at all is firing.
          { key: :exceptions, name: "Exceptions", url: -> { url_helpers.exceptions_path },
            healthy_label: "quiet", slow_label: "firing", description: exceptions_description },
          { key: :tracking, name: "Tracking", url: -> { url_helpers.storage_path },
            healthy_label: "writing", slow_label: "backlogged", critical_label: "dropping", hide_when_healthy: true },
          { key: :storage, name: "Storage", url: -> { url_helpers.storage_path }, hide_when_healthy: true }
        ]
      end

      def exceptions_description
        "Open exception groups in the #{@range_label}. " \
          "Quiet: no occurrences. Firing: raised at least once. " \
          "Critical: #{exception_thresholds[:critical]}+ occurrences. " \
          "Groups with #{exception_thresholds[:warning]}+ occurrences are listed under Needs Attention."
      end

      def build_areas
        area_definitions.filter_map do |definition|
          counts = @health[definition[:key]]
          next if counts.nil?

          area_state = state_for(counts)
          next if definition[:hide_when_healthy] && area_state == :ok

          build_area(definition, counts, area_state)
        end
      end

      def build_area(definition, counts, area_state)
        labels = {
          healthy: definition.fetch(:healthy_label, "healthy"),
          slow: definition.fetch(:slow_label, "slow"),
          critical: definition.fetch(:critical_label, "critical")
        }
        count, label, detail = figure_for(counts, labels)

        Area.new(
          key: definition[:key],
          name: definition[:name],
          state: area_state,
          url: definition[:url].call,
          description: definition[:description],
          labels: labels,
          count: count,
          label: label,
          detail: detail,
          meter: { critical: counts[:critical], warning: counts[:slow], ok: counts[:healthy] }.select { |_, value| value > 0 }
        )
      end

      def state_for(counts)
        return :critical if counts[:critical] > 0
        return :warning if counts[:slow] > 0

        :ok
      end

      # The big figure is what matters most: the problem count when there is
      # one, otherwise how many are healthy.
      def figure_for(counts, labels)
        total = counts.values_at(:healthy, :slow, :critical).sum
        troubled = counts[:critical] + counts[:slow]

        return [ 0, "tracked", "" ] if total.zero?
        return [ total, labels[:healthy], "" ] if troubled.zero?

        if counts[:critical] > 0 && counts[:slow] > 0
          # With two problem states the breakdown fills the line.
          [ troubled, "need attention", "#{counts[:critical]} #{labels[:critical]} · #{counts[:slow]} #{labels[:slow]}" ]
        else
          label = counts[:critical] > 0 ? labels[:critical] : labels[:slow]
          detail = counts[:healthy] > 0 ? "#{ActiveSupport::NumberHelper.number_to_delimited(counts[:healthy])} #{labels[:healthy]}" : ""
          [ troubled, label, detail ]
        end
      end

      def overall_state
        if @needs_attention[:critical].any? || areas.any? { |area| area.state == :critical }
          :critical
        elsif @needs_attention[:warning].any? || areas.any? { |area| area.state == :warning }
          :warning
        else
          :ok
        end
      end

      def troubled_areas
        areas.reject { |area| area.state == :ok }
      end

      # "9 exceptions firing", "1 route critical": each non-zero problem count,
      # named, so the headline says what is wrong rather than how bad.
      def problems
        @problems ||= troubled_areas.flat_map do |area|
          counts = @health[area.key]
          [
            (problem_phrase(counts[:critical], area.name, area.labels[:critical]) if counts[:critical] > 0),
            (problem_phrase(counts[:slow], area.name, area.labels[:slow]) if counts[:slow] > 0)
          ].compact
        end
      end

      def problem_phrase(count, name, label)
        noun = count == 1 ? name.downcase.singularize : name.downcase
        "#{ActiveSupport::NumberHelper.number_to_delimited(count)} #{noun} #{label}"
      end

      # Names the areas with something tracked and nothing wrong. An area with
      # nothing recorded in the range is left out: its cell says "0 tracked",
      # and calling that healthy would claim more than is known.
      def healthy_sentence
        names = areas.select { |area| area.state == :ok && tracked?(area) }.map { |area| area.name.downcase }
        return if names.empty?

        # "Storage is healthy", but "Jobs are healthy": a lone plural name
        # still takes a plural verb.
        singular = names.size == 1 && names.first == names.first.singularize
        "#{names.to_sentence.upcase_first} #{singular ? "is" : "are"} healthy."
      end

      def tracked?(area)
        @health[area.key].values_at(:healthy, :slow, :critical).sum > 0
      end

      def worst_linked_area
        troubled_areas.find { |area| area.state == :critical && area.url } || troubled_areas.find(&:url)
      end

      def attention_total
        @needs_attention[:total]
      end

      def critical_total
        @needs_attention[:critical].size
      end

      def warning_total
        @needs_attention[:warning].size
      end
    end
  end
end
