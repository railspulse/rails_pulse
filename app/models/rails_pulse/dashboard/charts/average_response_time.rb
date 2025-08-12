module RailsPulse
  module Dashboard
    module Charts
      class AverageResponseTime
        def to_chart_data
          # Create a range of all dates in the past 2 weeks
          start_date = 2.weeks.ago.beginning_of_day.to_date
          end_date = Time.current.to_date
          date_range = (start_date..end_date)

          # Get the actual data
          requests = RailsPulse::Request.where("occurred_at >= ?", start_date.beginning_of_day)
          actual_data = requests
            .group_by_day(:occurred_at)
            .average(:duration)

          # Fill in all dates with zero values for missing days
          date_range.each_with_object({}) do |date, result|
            formatted_date = date.strftime("%b %-d")
            avg_duration = actual_data[date]
            result[formatted_date] = avg_duration&.round(0) || 0
          end
        end
      end
    end
  end
end
