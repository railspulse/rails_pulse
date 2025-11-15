module RailsPulse
  module Jobs
    module Cards
      class AverageDuration < Base
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
            "SUM(avg_duration * count) AS total_weighted_duration",
            "SUM(count) AS total_runs",
            "SUM(CASE WHEN period_start >= #{quote(current_window_start)} THEN avg_duration * count ELSE 0 END) AS current_weighted_duration",
            "SUM(CASE WHEN period_start >= #{quote(current_window_start)} THEN count ELSE 0 END) AS current_runs",
            "SUM(CASE WHEN period_start >= #{quote(range_start)} AND period_start < #{quote(current_window_start)} THEN avg_duration * count ELSE 0 END) AS previous_weighted_duration",
            "SUM(CASE WHEN period_start >= #{quote(range_start)} AND period_start < #{quote(current_window_start)} THEN count ELSE 0 END) AS previous_runs"
          ).take

          total_runs = metrics&.total_runs.to_i
          total_weighted_duration = metrics&.total_weighted_duration.to_f
          current_runs = metrics&.current_runs.to_i
          current_weighted_duration = metrics&.current_weighted_duration.to_f
          previous_runs = metrics&.previous_runs.to_i
          previous_weighted_duration = metrics&.previous_weighted_duration.to_f

          average_duration = average_for(total_weighted_duration, total_runs)
          current_average = average_for(current_weighted_duration, current_runs)
          previous_average = average_for(previous_weighted_duration, previous_runs)

          trend_icon, trend_amount = trend_for(current_average, previous_average)

          grouped_weighted = base_query
            .group_by_day(:period_start, time_zone: "UTC")
            .sum(Arel.sql("avg_duration * count"))

          grouped_counts = base_query
            .group_by_day(:period_start, time_zone: "UTC")
            .sum(:count)

          sparkline_data = sparkline_from_averages(grouped_weighted, grouped_counts)

          {
            id: "jobs_average_duration",
            context: "jobs",
            title: "Average Duration",
            summary: format_duration(average_duration),
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to previous week"
          }
        end

        private

        def average_for(weighted_duration, total_runs)
          return 0.0 if total_runs.zero?

          (weighted_duration.to_f / total_runs).round(1)
        end

        def sparkline_from_averages(weighted_by_day, counts_by_day)
          start_date = range_start.to_date
          end_date = now.to_date

          (start_date..end_date).each_with_object({}) do |day, hash|
            weighted = weighted_by_day[day].to_f
            count = counts_by_day[day].to_f
            avg = count.zero? ? 0.0 : (weighted / count).round(1)
            label = day.strftime("%b %-d")
            hash[label] = { value: avg }
          end
        end
      end
    end
  end
end
