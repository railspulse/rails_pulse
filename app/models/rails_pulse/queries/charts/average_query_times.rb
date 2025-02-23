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
          if @query
            requests = @ransack_query.result(distinct: false)
              .public_send(@group_by, "occurred_at", series: true)
              .select(
                "occurred_at",
                "COALESCE(AVG(duration), 0) AS average_response_time_ms"
              )
            requests.each_with_object({}) do |result, hash|
              occurred_at = result.occurred_at
              occurred_at = Time.parse(occurred_at) if occurred_at.is_a?(String)
              normalized_occurred_at =
                case @group_by
                when :group_by_hour
                  occurred_at.beginning_of_hour
                when :group_by_day
                  occurred_at.beginning_of_day
                else
                  occurred_at
                end
              hash[normalized_occurred_at.to_i] = {
                value: result.average_response_time_ms.to_f
              }
            end
          else
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
end
