module RailsPulse
  module Queries
    module Charts
      class AverageQueryTimes < RailsPulse::Charts::Base
        def to_chart_data
          # The ransack query already contains the correct filters
          summaries = @ransack_query.result(distinct: false)
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: summarizable_type,
              period_type: @period_type
            )
          summaries = summaries.where(summarizable_id: @subject.id) if @subject

          summaries = summaries
            .group(:period_start)
            .having("AVG(avg_duration) > ?", @start_duration || 0)
            .average(:avg_duration)
            .transform_keys(&:to_i)

          # Pad missing data points with zeros using base class helper
          data = pad_data_with_zeros(summaries, @start_time, @end_time, time_step)

          # Convert timestamps to milliseconds for JavaScript Date compatibility
          data.transform_keys { |timestamp| timestamp * 1000 }
              .transform_values { |value| value.to_f.round(2) }
        end

        private

        def summarizable_type = "RailsPulse::Query"
      end
    end
  end
end
