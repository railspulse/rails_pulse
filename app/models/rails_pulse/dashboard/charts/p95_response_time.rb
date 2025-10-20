module RailsPulse
  module Dashboard
    module Charts
      class P95ResponseTime
        def initialize(disabled_tags: [], show_non_tagged: true)
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_chart_data
          # Create a range of all dates in the past 2 weeks
          start_date = 2.weeks.ago.beginning_of_day.to_date
          end_date = Time.current.to_date
          date_range = (start_date..end_date)

          # Get the actual data from Summary records (queries for P95)
          summaries = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Query",
              period_type: "day",
              period_start: start_date.beginning_of_day..end_date.end_of_day
            )

          actual_data = summaries
            .group_by_day(:period_start, time_zone: Time.zone)
            .average(:p95_duration)
            .transform_keys { |date| date.to_date }
            .transform_values { |avg| avg&.round(0) || 0 }

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
