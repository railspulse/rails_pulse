module RailsPulse
  module Jobs
    module Cards
      class TotalJobs < Base
        def initialize(job: nil)
          @job = job
        end

        def to_metric_card
          # When scoped to a job, show runs count instead of job count
          if @job
            base_query = RailsPulse::Summary
              .where(
                summarizable_type: "RailsPulse::Job",
                summarizable_id: @job.id,
                period_type: "day",
                period_start: range_start..now
              )

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
              id: "jobs_total_jobs",
              context: "jobs",
              title: "Total Runs",
              summary: "#{format_number(total_runs)} runs",
              chart_data: sparkline_from(grouped_runs),
              trend_icon: trend_icon,
              trend_amount: trend_amount,
              trend_text: "Compared to previous week"
            }
          else
            total_jobs = RailsPulse::Job.count

            current_new_jobs = RailsPulse::Job.where(created_at: current_window_start..now).count
            previous_new_jobs = RailsPulse::Job.where(created_at: range_start...current_window_start).count

            trend_icon, trend_amount = trend_for(current_new_jobs, previous_new_jobs)

            grouped_new_jobs = RailsPulse::Job
              .where(created_at: range_start..now)
              .group_by_day(:created_at, time_zone: "UTC")
              .count

            {
              id: "jobs_total_jobs",
              context: "jobs",
              title: "Total Jobs",
              summary: "#{format_number(total_jobs)} jobs",
              chart_data: sparkline_from(grouped_new_jobs),
              trend_icon: trend_icon,
              trend_amount: trend_amount,
              trend_text: "New jobs vs previous week"
            }
          end
        end
      end
    end
  end
end
