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
          percentile_column = "p#{percentile}_duration"

          current_metrics = calculate_period_metrics(summaries, last_7_days, Time.current, threshold, percentile_column)
          previous_metrics = calculate_period_metrics(summaries, previous_7_days, last_7_days, threshold, percentile_column)

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
            total_count_day = day_summaries.sum { |s| s.count || 0 }

            excess = if total_count_day > 0
              fleet_percentile = day_summaries.sum { |s| (s.public_send(percentile_column) || 0) * (s.count || 0) }.to_f / total_count_day
              [ fleet_percentile - threshold, 0 ].max.round(1)
            else
              0.0
            end

            label = day.strftime("%b %-d")
            sparkline_data[label] = { value: excess }
          end

          all_clear = total_count > 0 && total_over == 0

          {
            id: "#{base_card_id}_p#{percentile}",
            context: card_context,
            title: "P#{percentile} #{base_card_title}",
            summary: "#{overall_percentage}%",
            all_clear: all_clear,
            chart_data: sparkline_data,
            chart_color: percentile == 95 ? RailsPulse::ChartColors::P95 : RailsPulse::ChartColors::P99,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week"
          }
        end
      end

      private

      def calculate_period_metrics(summaries, start_time, end_time, threshold, percentile_column)
        period_summaries = summaries.select do |s|
          s.period_start >= start_time && s.period_start < end_time
        end

        total_over = 0
        total_count = 0

        period_summaries.group_by { |s| s.period_start.to_date }.each do |_day, day_summaries|
          day_count = day_summaries.sum { |s| s.count || 0 }
          next if day_count == 0

          fleet_percentile = day_summaries.sum { |s| (s.public_send(percentile_column) || 0) * (s.count || 0) }.to_f / day_count
          total_count += day_count
          total_over += fleet_percentile > threshold ? day_count : 0
        end

        { total_over: total_over, total_count: total_count }
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
