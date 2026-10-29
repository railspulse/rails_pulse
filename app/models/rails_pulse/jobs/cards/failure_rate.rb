module RailsPulse
  module Jobs
    module Cards
      class FailureRate < RailsPulse::Cards::Base
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
            window_sql("SUM(CASE WHEN rails_pulse_summaries.period_start >= :current_start THEN rails_pulse_summaries.count ELSE 0 END) AS current_count"),
            window_sql("SUM(CASE WHEN rails_pulse_summaries.period_start >= :current_start THEN rails_pulse_summaries.error_count ELSE 0 END) AS current_errors"),
            window_sql("SUM(CASE WHEN rails_pulse_summaries.period_start >= :range_start AND rails_pulse_summaries.period_start < :current_start THEN rails_pulse_summaries.count ELSE 0 END) AS previous_count"),
            window_sql("SUM(CASE WHEN rails_pulse_summaries.period_start >= :range_start AND rails_pulse_summaries.period_start < :current_start THEN rails_pulse_summaries.error_count ELSE 0 END) AS previous_errors")
          ).take

          current_runs = metrics&.current_count.to_i
          current_errors = metrics&.current_errors.to_i
          previous_runs = metrics&.previous_count.to_i
          previous_errors = metrics&.previous_errors.to_i

          current_rate = rate_for(current_errors, current_runs)
          previous_rate = rate_for(previous_errors, previous_runs)

          trend_icon, trend_amount = trend_for(current_rate, previous_rate) if show_trend?

          # Create a separate query for sparkline data using only the current period
          sparkline_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Job",
              period_type: @period_type,
              period_start: current_window_start..now
            )
          sparkline_query = sparkline_query.where(summarizable_id: @subject.id) if @subject

          grouped_errors = bucket_by_period(sparkline_query) { |relation| relation.sum("rails_pulse_summaries.error_count") }
          grouped_counts = bucket_by_period(sparkline_query) { |relation| relation.sum("rails_pulse_summaries.count") }

          sparkline_data = sparkline_from_failure_rates(grouped_errors, grouped_counts)

          {
            id: "jobs_failure_rate",
            chart_color: RailsPulse::ChartColors::DEFAULT,
            context: "jobs",
            title: "Failure Rate",
            summary: "#{format_percentage(current_rate, 1)}",
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: (show_trend? ? comparison_period_text : nil),
            period_stat: current_runs > 0 ? "#{format_number(current_errors)} failures · #{format_number(current_runs)} runs" : period_date_range,
            help_heading: "Failure Rate",
            help_text: "Percentage of job executions that raised an error over the selected range. A rising failure rate may indicate bugs, external dependency issues, or jobs receiving invalid data."
          }
        end

        private

        def rate_for(errors, total)
          return 0.0 if total.zero?

          (errors.to_f / total * 100).round(1)
        end

        def sparkline_from_failure_rates(errors_by_period, counts_by_period)
          rates = counts_by_period.each_with_object({}) do |(period, total), hash|
            hash[period] = rate_for(errors_by_period[period].to_f, total.to_f)
          end
          sparkline_from(rates)
        end
      end
    end
  end
end
