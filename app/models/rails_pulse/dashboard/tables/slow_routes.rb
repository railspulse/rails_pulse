module RailsPulse
  module Dashboard
    module Tables
      class SlowRoutes
        include RailsPulse::FormattingHelper
        def to_table_data
          # Get data for this week
          this_week_start = 1.week.ago.beginning_of_week
          this_week_end = Time.current.end_of_week

          # Fetch route data for this week
          route_data = RailsPulse::Request.joins(:route)
            .where(occurred_at: this_week_start..this_week_end)
            .group("rails_pulse_routes.path, rails_pulse_routes.id")
            .select("rails_pulse_routes.path, rails_pulse_routes.id, AVG(rails_pulse_requests.duration) as avg_duration, COUNT(*) as request_count, MAX(rails_pulse_requests.occurred_at) as last_seen")
            .order("avg_duration DESC")
            .limit(5)

          # Build data rows
          data_rows = route_data.map do |record|
            {
              route_path: record.path,
              route_id: record.id,
              route_link: "/rails_pulse/routes/#{record.id}",
              average_time: record.avg_duration.to_f.round(0),
              request_count: record.request_count,
              last_request: time_ago_in_words(record.last_seen)
            }
          end

          # Return new structure with columns and data
          {
            columns: [
              { field: :route_path, label: "Route", link_to: :route_link, class: "w-auto" },
              { field: :average_time, label: "Average Time", class: "w-32" },
              { field: :request_count, label: "Requests", class: "w-24" },
              { field: :last_request, label: "Last Request", class: "w-32" }
            ],
            data: data_rows
          }
        end

      end
    end
  end
end
