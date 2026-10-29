module RailsPulse
  module Jobs
    module Cards
      class P95Duration < RailsPulse::Cards::Base
        def initialize(job: nil, period: 14, **kwargs)
          super(subject: job, period: period, **kwargs)
        end

        def to_metric_card
          base_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Job",
              period_type: @period_type,
              period_start: range_start..now
            )
          base_query = base_query.where(summarizable_id: @subject.id) if @subject

          metrics = base_query.select(
            window_sql("SUM(CASE WHEN rails_pulse_summaries.period_start >= :current_start THEN rails_pulse_summaries.p95_duration * rails_pulse_summaries.count ELSE 0 END) AS current_weighted_p95"),
            window_sql("SUM(CASE WHEN rails_pulse_summaries.period_start >= :current_start THEN rails_pulse_summaries.count ELSE 0 END) AS current_runs"),
            window_sql("SUM(CASE WHEN rails_pulse_summaries.period_start >= :range_start AND rails_pulse_summaries.period_start < :current_start THEN rails_pulse_summaries.p95_duration * rails_pulse_summaries.count ELSE 0 END) AS previous_weighted_p95"),
            window_sql("SUM(CASE WHEN rails_pulse_summaries.period_start >= :range_start AND rails_pulse_summaries.period_start < :current_start THEN rails_pulse_summaries.count ELSE 0 END) AS previous_runs")
          ).take

          current_runs = metrics&.current_runs.to_i
          current_weighted_p95 = metrics&.current_weighted_p95.to_f
          previous_runs = metrics&.previous_runs.to_i
          previous_weighted_p95 = metrics&.previous_weighted_p95.to_f

          current_p95 = weighted_average(current_weighted_p95, current_runs)
          previous_p95 = weighted_average(previous_weighted_p95, previous_runs)

          baseline = baseline_trend_for(@subject, metric: :p95)

          if baseline
            trend_icon, trend_amount, trend_caption = baseline
          elsif show_trend?
            trend_icon, trend_amount = trend_for(current_p95, previous_p95)
          end

          grouped_weighted = bucket_by_period(base_query) { |relation| relation.sum(Arel.sql("rails_pulse_summaries.p95_duration * rails_pulse_summaries.count")) }
          grouped_counts = bucket_by_period(base_query) { |relation| relation.sum("rails_pulse_summaries.count") }

          sparkline_data = sparkline_from_averages(grouped_weighted, grouped_counts)

          {
            id: "jobs_p95_duration",
            chart_color: RailsPulse::ChartColors::P95,
            context: "jobs",
            title: "95th Percentile Duration",
            summary: format_duration(current_p95),
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: trend_caption || (show_trend? ? comparison_period_text : nil),
            period_stat: current_runs > 0 ? "Across #{format_number(current_runs)} runs" : period_date_range,
            help_heading: "P95 Duration",
            help_text: "The 95th percentile execution time — 95% of jobs complete faster than this. Weighted by job volume across all classes. A rising P95 indicates jobs are becoming slower, which may cause queue backlog."
          }
        end

        private

        def weighted_average(weighted_duration, total_runs)
          return 0.0 if total_runs.zero?

          (weighted_duration.to_f / total_runs).round(1)
        end

        # Averages are keyed by the periods that actually have a summary row;
        # sparkline_from fills the remaining buckets with zero or a ghost.
        def sparkline_from_averages(weighted_by_period, counts_by_period)
          averages = counts_by_period.each_with_object({}) do |(period, count), hash|
            hash[period] = count.to_f.zero? ? 0.0 : (weighted_by_period[period].to_f / count).round(1)
          end
          sparkline_from(averages)
        end
      end
    end
  end
end
