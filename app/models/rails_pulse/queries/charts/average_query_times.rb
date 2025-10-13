module RailsPulse
  module Queries
    module Charts
      class AverageQueryTimes
        def initialize(ransack_query:, period_type: nil, query: nil, start_time: nil, end_time: nil, start_duration: nil)
          @ransack_query = ransack_query
          @period_type = period_type
          @query = query
          @start_time = start_time
          @end_time = end_time
          @start_duration = start_duration
        end

        def to_rails_chart
          # The ransack query already contains the correct filters, just add period_type
          summaries = @ransack_query.result(distinct: false)
            .where(period_type: @period_type)
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
