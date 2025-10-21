module RailsPulse
  module Dashboard
    module Charts
      class AverageResponseTime
        def initialize(disabled_tags: [], show_non_tagged: true)
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_chart_data
          # Create a range of all dates in the past 2 weeks
          start_date = 2.weeks.ago.beginning_of_day.to_date
          end_date = Time.current.to_date
          date_range = (start_date..end_date)

          # Get the actual data from Summary records (routes)
          summaries = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: "day",
              period_start: start_date.beginning_of_day..end_date.end_of_day
            )

          # Group by day manually for cross-database compatibility
          actual_data = {}
          summaries.each do |summary|
            date = summary.period_start.to_date

            if actual_data[date]
              actual_data[date][:total_weighted] += (summary.avg_duration || 0) * (summary.count || 0)
              actual_data[date][:total_count] += (summary.count || 0)
            else
              actual_data[date] = {
                total_weighted: (summary.avg_duration || 0) * (summary.count || 0),
                total_count: (summary.count || 0)
              }
            end
          end

          # Convert to final values
          actual_data = actual_data.transform_values do |data|
            data[:total_count] > 0 ? (data[:total_weighted] / data[:total_count]).round(0) : 0
          end

          # Fill in all dates with zero values for missing days
          date_range.each_with_object({}) do |date, result|
            formatted_date = date.strftime("%b %-d")
            result[formatted_date] = actual_data[date] || 0
          end
        end
      end
    end
  end
end
