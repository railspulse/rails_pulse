module RailsPulse
  module Cards
    class OverThresholdBase
      def initialize(subject:, disabled_tags: [], show_non_tagged: true)
        @subject = subject
        @disabled_tags = disabled_tags
        @show_non_tagged = show_non_tagged
      end

      def to_metric_cards
        slo_configs = RailsPulse.configuration.public_send(slo_config_key)
        return [] if slo_configs.empty?

        last_7_days = 7.days.ago.beginning_of_day
        previous_7_days = 14.days.ago.beginning_of_day

        # Query summaries once for all SLOs
        base_query = RailsPulse::Summary
          .with_tag_filters(@disabled_tags, @show_non_tagged)
          .where(
            summarizable_type: summarizable_type,
            period_type: "day",
            period_start: 2.weeks.ago.beginning_of_day..Time.current
          )
        base_query = base_query.where(summarizable_id: @subject.id) if @subject

        summaries = base_query.to_a

        start_day = 2.weeks.ago.beginning_of_day.to_date
        end_day = Time.current.to_date

        slo_configs.map do |slo|
          threshold = slo[:threshold]
          percentile = slo[:percentile]

          current_metrics = calculate_period_metrics(summaries, last_7_days, Time.current, threshold)
          previous_metrics = calculate_period_metrics(summaries, previous_7_days, last_7_days, threshold)

          total_over = current_metrics[:total_over] + previous_metrics[:total_over]
          total_count = current_metrics[:total_count] + previous_metrics[:total_count]
          overall_percentage = total_count > 0 ? (total_over.to_f / total_count * 100).round(1) : 0

          current_percentage = current_metrics[:total_count] > 0 ?
            (current_metrics[:total_over].to_f / current_metrics[:total_count] * 100) : 0
          previous_percentage = previous_metrics[:total_count] > 0 ?
            (previous_metrics[:total_over].to_f / previous_metrics[:total_count] * 100) : 0

          percentage_diff = previous_percentage.zero? ? 0 :
            ((current_percentage - previous_percentage) / previous_percentage * 100).abs.round(1)

          trend_icon = percentage_diff < 0.1 ? "move-right" :
            current_percentage < previous_percentage ? "trending-down" : "trending-up"
          trend_amount = previous_percentage.zero? ? "0%" : "#{percentage_diff}%"

          sparkline_data = {}
          (start_day..end_day).each do |day|
            day_summaries = summaries.select { |s| s.period_start.to_date == day }

            total_over_day = 0
            total_count_day = 0

            day_summaries.each do |summary|
              count = summary.count || 0
              over_count = estimate_over_threshold(summary, threshold)
              total_over_day += over_count
              total_count_day += count
            end

            percentage = total_count_day > 0 ?
              (total_over_day.to_f / total_count_day * 100).round(1) : 0

            label = day.strftime("%b %-d")
            sparkline_data[label] = { value: percentage }
          end

          {
            id: "#{base_card_id}_p#{percentile}",
            context: card_context,
            title: "P#{percentile} #{base_card_title}",
            summary: "#{overall_percentage}%",
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week"
          }
        end
      end

      private

      def calculate_period_metrics(summaries, start_time, end_time, threshold)
        period_summaries = summaries.select do |s|
          s.period_start >= start_time && s.period_start < end_time
        end

        total_over = 0
        total_count = 0

        period_summaries.each do |summary|
          count = summary.count || 0
          over_count = estimate_over_threshold(summary, threshold)
          total_over += over_count
          total_count += count
        end

        { total_over: total_over, total_count: total_count }
      end

      # Estimate number of records over threshold using percentile data.
      # This is an approximation based on available percentile information.
      def estimate_over_threshold(summary, threshold)
        count = summary.count || 0
        return 0 if count == 0

        p50 = summary.p50_duration || 0
        p95 = summary.p95_duration || 0
        p99 = summary.p99_duration || 0

        if threshold <= p50
          # At least 50% are over threshold
          (count * 0.50).round
        elsif threshold <= p95
          # Between 5% and 50% are over threshold
          # Linear interpolation between p50 (50%) and p95 (5%)
          return (count * 0.50).round if (p95 - p50).zero?
          ratio = (p95 - threshold).to_f / (p95 - p50)
          percentage = 0.05 + (0.45 * ratio)
          (count * percentage).round
        elsif threshold <= p99
          # Between 1% and 5% are over threshold
          # Linear interpolation between p95 (5%) and p99 (1%)
          return (count * 0.05).round if (p99 - p95).zero?
          ratio = (p99 - threshold).to_f / (p99 - p95)
          percentage = 0.01 + (0.04 * ratio)
          (count * percentage).round
        else
          # Less than 1% are over threshold
          # Assume linear drop-off after p99
          max_duration = summary.max_duration || p99
          return 0 if max_duration <= threshold
          ratio = (max_duration - threshold).to_f / (max_duration - p99)
          (count * 0.01 * ratio).round
        end
      end

      # Abstract methods — must be implemented by subclasses
      def slo_config_key = raise(NotImplementedError)
      def summarizable_type = raise(NotImplementedError)
      def base_card_id = raise(NotImplementedError)
      def base_card_title = raise(NotImplementedError)
      def card_context = raise(NotImplementedError)
    end
  end
end
