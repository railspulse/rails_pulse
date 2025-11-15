module RailsPulse
  module Jobs
    module Cards
      class TotalRuns < Base
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
            "SUM(CASE WHEN period_start >= #{quote(current_window_start)} THEN count ELSE 0 END) AS current_count",
            "SUM(CASE WHEN period_start >= #{quote(range_start)} AND period_start < #{quote(current_window_start)} THEN count ELSE 0 END) AS previous_count"
          ).take

          total_runs = metrics&.total_count.to_i
          current_runs = metrics&.current_count.to_i
          previous_runs = metrics&.previous_count.to_i

          trend_icon, trend_amount = trend_for(current_runs, previous_runs)

          grouped_runs = base_query
            .group_by_day(:period_start, time_zone: "UTC")
            .sum(:count)

          {
            id: "jobs_total_runs",
            context: "jobs",
            title: "Job Runs",
            summary: "#{format_number(total_runs)} runs",
            chart_data: sparkline_from(grouped_runs),
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to previous week"
          }
        end
      end
    end
  end
end
