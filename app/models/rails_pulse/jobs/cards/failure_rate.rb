module RailsPulse
  module Jobs
    module Cards
      class FailureRate < Base
        def initialize(job: nil)
          @job = job
        end

        def to_metric_card
          base_query = RailsPulse::Summary
            .where(
              summarizable_type: "RailsPulse::Job",
              period_type: "day",
              period_start: range_start..now
            )
          base_query = base_query.where(summarizable_id: @job.id) if @job

          metrics = base_query.select(
            "SUM(count) AS total_count",
            "SUM(error_count) AS total_errors",
            "SUM(CASE WHEN period_start >= #{quote(current_window_start)} THEN count ELSE 0 END) AS current_count",
            "SUM(CASE WHEN period_start >= #{quote(current_window_start)} THEN error_count ELSE 0 END) AS current_errors",
            "SUM(CASE WHEN period_start >= #{quote(range_start)} AND period_start < #{quote(current_window_start)} THEN count ELSE 0 END) AS previous_count",
            "SUM(CASE WHEN period_start >= #{quote(range_start)} AND period_start < #{quote(current_window_start)} THEN error_count ELSE 0 END) AS previous_errors"
          ).take

          total_runs = metrics&.total_count.to_i
          total_errors = metrics&.total_errors.to_i
          current_runs = metrics&.current_count.to_i
          current_errors = metrics&.current_errors.to_i
          previous_runs = metrics&.previous_count.to_i
          previous_errors = metrics&.previous_errors.to_i

          failure_rate = rate_for(total_errors, total_runs)
          current_rate = rate_for(current_errors, current_runs)
          previous_rate = rate_for(previous_errors, previous_runs)

          trend_icon, trend_amount = trend_for(current_rate, previous_rate)

          grouped_errors = base_query
            .group_by_day(:period_start, time_zone: "UTC")
            .sum(:error_count)

          grouped_counts = base_query
            .group_by_day(:period_start, time_zone: "UTC")
            .sum(:count)

          sparkline_data = sparkline_from_failure_rates(grouped_errors, grouped_counts)

          {
            id: "jobs_failure_rate",
            context: "jobs",
            title: "Failure Rate",
            summary: "#{format_percentage(failure_rate, 1)}",
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to previous week"
          }
        end

        private

        def rate_for(errors, total)
          return 0.0 if total.zero?

          (errors.to_f / total * 100).round(1)
        end

        def sparkline_from_failure_rates(errors_by_day, counts_by_day)
          start_date = range_start.to_date
          end_date = now.to_date

          (start_date..end_date).each_with_object({}) do |day, hash|
            errors = errors_by_day[day].to_f
            total = counts_by_day[day].to_f
            rate = total.zero? ? 0.0 : (errors / total * 100).round(1)
            label = day.strftime("%b %-d")
            hash[label] = { value: rate }
          end
        end
      end
    end
  end
end
