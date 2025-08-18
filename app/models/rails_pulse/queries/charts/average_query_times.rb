module RailsPulse
  module Queries
    module Charts
      class AverageQueryTimes
        def initialize(ransack_query:, group_by: :group_by_day, query: nil)
          @ransack_query = ransack_query
          @group_by = group_by
          @query = query
        end

        def to_rails_chart
          # Let groupdate handle the grouping and series filling
          actual_data = if @query
            @ransack_query.result(distinct: false)
              .public_send(@group_by, "occurred_at", series: true, time_zone: "UTC")
              .average(:duration)
          else
            @ransack_query.result(distinct: false)
              .left_joins(:operations)
              .public_send(@group_by, "rails_pulse_operations.occurred_at", series: true, time_zone: "UTC")
              .average("rails_pulse_operations.duration")
          end

          # Convert to the format expected by rails_charts
          actual_data.transform_keys do |k|
            if k.respond_to?(:to_i)
              k.to_i
            else
              # For Date objects, use beginning_of_day to get consistent UTC timestamps
              k.is_a?(Date) ? k.beginning_of_day.to_i : k.to_time.to_i
            end
          end.transform_values { |v| { value: v.to_f } }
        end
      end
    end
  end
end
