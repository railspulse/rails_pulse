module RailsPulse
  module Dashboard
    module Tables
      class SlowRoutes
        include RailsPulse::FormattingHelper
        
        def to_table_data
          # Get data for this week and last week
          this_week_start = 1.week.ago.beginning_of_week
          this_week_end = Time.current.end_of_week
          last_week_start = 2.weeks.ago.beginning_of_week
          last_week_end = 1.week.ago.beginning_of_week

          # Get this week's data
          this_week_data = RailsPulse::Request.joins(:route)
            .where(occurred_at: this_week_start..this_week_end)
            .group("rails_pulse_routes.path, rails_pulse_routes.id")
            .select("rails_pulse_routes.path, rails_pulse_routes.id, AVG(rails_pulse_requests.duration) as avg_duration, COUNT(*) as request_count")
            .order("avg_duration DESC")
            .limit(5)

          # Get last week's data for comparison
          last_week_averages = RailsPulse::Request.joins(:route)
            .where(occurred_at: last_week_start..last_week_end)
            .group("rails_pulse_routes.path")
            .average("rails_pulse_requests.duration")

          # Build result array matching test expectations
          this_week_data.map do |record|
            this_week_avg = record.avg_duration.to_f.round(0)
            last_week_avg = last_week_averages[record.path]&.round(0) || 0
            
            # Calculate percentage change
            percentage_change = if last_week_avg == 0
              this_week_avg > 0 ? 100.0 : 0.0
            else
              ((this_week_avg - last_week_avg) / last_week_avg.to_f * 100).round(1)
            end

            # Determine trend (worse = slower response times)
            trend = if last_week_avg == 0
              this_week_avg > 0 ? "worse" : "stable"
            elsif this_week_avg > last_week_avg
              "worse"  # Slower = worse
            elsif this_week_avg < last_week_avg
              "better" # Faster = better
            else
              "stable"
            end

            {
              route_path: record.path,
              this_week_avg: this_week_avg,
              last_week_avg: last_week_avg,
              percentage_change: percentage_change,
              request_count: record.request_count,
              trend: trend
            }
          end
        end
      end
    end
  end
end
