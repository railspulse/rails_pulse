module RailsPulse
  module Routes
    module Charts
      class AverageQueryTimes
        def initialize(ransack_query:, group_by: :group_by_day, route: nil)
          @ransack_query = ransack_query
          @group_by = group_by
          @route = route
        end

        def to_rails_chart
          requests = @ransack_query.result(distinct: false)
            .includes(:operations)
            .left_joins(:operations)
            .public_send(
              @group_by,
              "rails_pulse_operations.occurred_at",
              series: true
            )
            .select(
              "rails_pulse_operations.occurred_at",
              "COALESCE(AVG(rails_pulse_operations.duration), 0) AS average_query_time_ms"
            )

            requests.each_with_object({}) do |result, hash|
              occurred_at = result.occurred_at
              occurred_at = Time.parse(occurred_at) if occurred_at.is_a?(String)
              hash[occurred_at.to_i] = {
                value: result.average_query_time_ms.to_f
              }
            end
        end
      end
    end
  end
end
