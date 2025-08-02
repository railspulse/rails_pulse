module RailsPulse
  module Dashboard
    module Tables
      class SlowRoutes
        def to_table_data
          # Get data for this week and last week separately
          this_week_start = 1.week.ago.beginning_of_week
          this_week_end = Time.current.end_of_week
          last_week_start = 2.weeks.ago.beginning_of_week
          last_week_end = 1.week.ago.end_of_week

          # Fetch this week's data
          this_week_data = RailsPulse::Request.joins(:route)
            .where(occurred_at: this_week_start..this_week_end)
            .group("rails_pulse_routes.path")
            .select("rails_pulse_routes.path, AVG(rails_pulse_requests.duration) as avg_duration, COUNT(*) as request_count")
            .each_with_object({}) do |record, hash|
              hash[record.path] = {
                avg_duration: record.avg_duration.to_f.round(0),
                request_count: record.request_count
              }
            end

          # Fetch last week's data
          last_week_data = RailsPulse::Request.joins(:route)
            .where(occurred_at: last_week_start..last_week_end)
            .group("rails_pulse_routes.path")
            .select("rails_pulse_routes.path, AVG(rails_pulse_requests.duration) as avg_duration")
            .each_with_object({}) do |record, hash|
              hash[record.path] = record.avg_duration.to_f.round(0)
            end

          # Merge data and calculate changes
          combined_data = this_week_data.map do |route_path, this_week_info|
            last_week_avg = last_week_data[route_path] || 0
            this_week_avg = this_week_info[:avg_duration]

            percentage_change = if last_week_avg.zero?
              this_week_avg > 0 ? 100.0 : 0.0
            else
              ((this_week_avg - last_week_avg) / last_week_avg * 100).round(1)
            end

            {
              route_path: route_path,
              this_week_avg: this_week_avg,
              last_week_avg: last_week_avg,
              percentage_change: percentage_change,
              request_count: this_week_info[:request_count],
              trend: percentage_change > 5 ? "worse" : (percentage_change < -5 ? "better" : "stable")
            }
          end

          # Sort by this week's average (slowest first) and take top 5
          combined_data.sort_by { |route| -route[:this_week_avg] }.first(5)
        end
      end
    end
  end
end
