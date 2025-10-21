module RailsPulse
  module Routes
    module Charts
      class AverageResponseTimes
        def initialize(ransack_query:, period_type: nil, route: nil, start_time: nil, end_time: nil, start_duration: nil, disabled_tags: [], show_non_tagged: true)
          @ransack_query = ransack_query
          @period_type = period_type
          @route = route
          @start_time = start_time
          @end_time = end_time
          @start_duration = start_duration
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_rails_chart
          summaries = @ransack_query.result(distinct: false)
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: @period_type
            )

          summaries = summaries.where(summarizable_id: @route.id) if @route
          summaries = summaries
            .group(:period_start)
            .having("AVG(avg_duration) > ?", @start_duration || 0)
            .average(:avg_duration)
            .transform_keys(&:to_i)

          # Pad missing data points with zeros
          step = @period_type == :hour ? 1.hour : 1.day
          data = {}
          (@start_time.to_i..@end_time.to_i).step(step) do |timestamp|
            data[timestamp.to_i] = summaries[timestamp.to_i].to_f.round(2)
          end
          data
        end
      end
    end
  end
end
