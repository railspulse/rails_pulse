module RailsPulse
  module Dashboard
    module Charts
      class AverageResponseTime
        def to_chart_data
          requests = RailsPulse::Request.where("occurred_at >= ?", 2.weeks.ago.beginning_of_day)

          requests
            .group_by_day(:occurred_at)
            .average(:duration)
            .transform_keys { |date| date.strftime("%b %-d") }
            .transform_values { |avg| avg&.round(0) || 0 }
        end
      end
    end
  end
end
