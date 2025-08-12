module RailsPulse
  module Dashboard
    module Tables
      class SlowQueries
        include RailsPulse::FormattingHelper
        def to_table_data
          # Get data for this week
          this_week_start = 1.week.ago.beginning_of_week
          this_week_end = Time.current.end_of_week

          # Fetch query data for this week
          query_data = RailsPulse::Operation.joins(:query)
            .where(occurred_at: this_week_start..this_week_end)
            .group("rails_pulse_queries.id, rails_pulse_queries.normalized_sql")
            .select("rails_pulse_queries.id, rails_pulse_queries.normalized_sql, AVG(rails_pulse_operations.duration) as avg_duration, COUNT(*) as request_count, MAX(rails_pulse_operations.occurred_at) as last_seen")
            .order("avg_duration DESC")
            .limit(5)

          # Build data rows
          data_rows = query_data.map do |record|
            {
              query_text: truncate_query(record.normalized_sql),
              query_id: record.id,
              query_link: "/rails_pulse/queries/#{record.id}",
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
          if cleaned_sql.length > 38
            "#{cleaned_sql[0..35]}..."
          else
            cleaned_sql
          end
        end
      end
    end
  end
end
