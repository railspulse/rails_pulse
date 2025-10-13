module RailsPulse
  module Dashboard
    module Tables
      class SlowQueries
        include RailsPulse::FormattingHelper
        def to_table_data
          # Get data for this week
          this_week_start = 1.week.ago.beginning_of_week
          this_week_end = Time.current.end_of_week

          # Fetch query data from Summary records for this week
          query_data = RailsPulse::Summary
            .joins("INNER JOIN rails_pulse_queries ON rails_pulse_queries.id = rails_pulse_summaries.summarizable_id")
            .where(
              summarizable_type: "RailsPulse::Query",
              period_type: "day",
              period_start: this_week_start..this_week_end
            )
            .group("rails_pulse_summaries.summarizable_id, rails_pulse_queries.normalized_sql")
            .select(
              "rails_pulse_summaries.summarizable_id as query_id",
              "rails_pulse_queries.normalized_sql",
              "SUM(rails_pulse_summaries.avg_duration * rails_pulse_summaries.count) / SUM(rails_pulse_summaries.count) as avg_duration",
              "SUM(rails_pulse_summaries.count) as request_count",
              "MAX(rails_pulse_summaries.period_end) as last_seen"
            )
            .order("avg_duration DESC")
            .limit(5)

          # Build data rows
          data_rows = query_data.map do |record|
            {
              query_text: truncate_query(record.normalized_sql),
              query_id: record.query_id,
              query_link: RailsPulse::Engine.routes.url_helpers.query_path(record.query_id),
              average_time: record.avg_duration.to_f.round(0),
              request_count: record.request_count,
              last_request: time_ago_in_words(record.last_seen)
            }
          end

          # Return new structure with columns and data
          {
            columns: [
              { field: :query_text, label: "Query", link_to: :query_link, class: "w-auto" },
              { field: :average_time, label: "Average Time", class: "w-32" },
              { field: :request_count, label: "Requests", class: "w-24" },
              { field: :last_request, label: "Last Request", class: "w-32" }
            ],
            data: data_rows
          }
        end

        private

        def truncate_query(sql)
          return "" if sql.blank?

          # Remove extra whitespace and truncate
          cleaned_sql = sql.gsub(/\s+/, " ").strip
          if cleaned_sql.length > 80
            "#{cleaned_sql[0..79]}..."
          else
            cleaned_sql
          end
        end
      end
    end
  end
end
