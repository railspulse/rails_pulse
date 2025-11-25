module RailsPulse
  module Dashboard
    module Tables
      class SlowRoutes
        include RailsPulse::FormattingHelper

        def initialize(disabled_tags: [], show_non_tagged: true)
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_table_data
          # Get data for this week
          this_week_start = 1.week.ago.beginning_of_week
          this_week_end = Time.current.end_of_week

          # Fetch route data from Summary records for this week
          route_data = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .joins("INNER JOIN rails_pulse_routes ON rails_pulse_routes.id = rails_pulse_summaries.summarizable_id")
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: "day",
              period_start: this_week_start..this_week_end
            )
            .group("rails_pulse_summaries.summarizable_id, rails_pulse_routes.path")
            .select(
              "rails_pulse_summaries.summarizable_id as route_id",
              "rails_pulse_routes.path",
              "SUM(rails_pulse_summaries.avg_duration * rails_pulse_summaries.count) / SUM(rails_pulse_summaries.count) as avg_duration",
              "SUM(rails_pulse_summaries.count) as request_count",
              "MAX(rails_pulse_summaries.period_end) as last_seen"
            )
            .order("avg_duration DESC")
            .limit(5)

          # Build data rows
          data_rows = route_data.map do |record|
            {
              route_path: record.path,
              route_id: record.route_id,
              route_link: RailsPulse::Engine.routes.url_helpers.route_path(record.route_id),
              average_time: record.avg_duration.to_f.round(0),
              request_count: record.request_count,
              last_request: time_ago_in_words(record.last_seen)
            }
          end

          # Return new structure with columns and data
          {
            columns: [
              { field: :route_path, label: "Route", link_to: :route_link, class: "w-48", cell_class: "truncate-cell" },
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
