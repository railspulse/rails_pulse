module RailsPulse
  # Merges source into target: combine http_methods, reassign requests and summaries, destroy source.
  # Used when two routes would collide on the unique [controller_action, path] index.
  class RouteMerger
    METRIC_SUM_COLUMNS = %w[
      count error_count success_count total_duration
      status_2xx status_3xx status_4xx status_5xx
    ].freeze

    WEIGHTED_AVG_COLUMNS = %w[
      avg_duration p50_duration p95_duration p99_duration
    ].freeze

    def self.call(target:, source:)
      new(target, source).call
    end

    def initialize(target, source)
      @target = target
      @source = source
    end

    def call
      return if @target.id == @source.id

      @source.http_methods_list.each { |m| @target.add_http_method(m) }
      RailsPulse::Route.transaction do
        @source.requests.update_all(route_id: @target.id)
        reassign_or_merge_summaries!
        @source.destroy!
      end
    end

    private

    def reassign_or_merge_summaries!
      source_summaries = RailsPulse::Summary.where(
        summarizable_type: "RailsPulse::Route",
        summarizable_id: @source.id
      )

      source_summaries.find_each do |source_summary|
        target_summary = RailsPulse::Summary.find_by(
          summarizable_type: "RailsPulse::Route",
          summarizable_id: @target.id,
          period_type: source_summary.period_type,
          period_start: source_summary.period_start
        )

        if target_summary
          merge_summary_metrics!(target_summary, source_summary)
          source_summary.destroy!
        else
          source_summary.update_column(:summarizable_id, @target.id)
        end
      end
    end

    def merge_summary_metrics!(target_summary, source_summary)
      target_count = target_summary.count.to_i
      source_count = source_summary.count.to_i
      combined_count = target_count + source_count

      attrs = {}

      METRIC_SUM_COLUMNS.each do |column|
        next unless target_summary.has_attribute?(column)

        attrs[column] = target_summary.public_send(column).to_f + source_summary.public_send(column).to_f
      end

      if combined_count.positive?
        WEIGHTED_AVG_COLUMNS.each do |column|
          next unless target_summary.has_attribute?(column)

          target_value = target_summary.public_send(column)
          source_value = source_summary.public_send(column)
          next if target_value.nil? && source_value.nil?

          attrs[column] = (
            (target_value.to_f * target_count) + (source_value.to_f * source_count)
          ) / combined_count
        end
      end

      if target_summary.has_attribute?(:min_duration)
        mins = [ target_summary.min_duration, source_summary.min_duration ].compact
        attrs[:min_duration] = mins.min if mins.any?
      end

      if target_summary.has_attribute?(:max_duration)
        maxes = [ target_summary.max_duration, source_summary.max_duration ].compact
        attrs[:max_duration] = maxes.max if maxes.any?
      end

      target_summary.update_columns(attrs.merge(updated_at: Time.current))
    end
  end
end
