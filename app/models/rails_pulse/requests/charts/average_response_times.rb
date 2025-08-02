module RailsPulse
  module Requests
    module Charts
      class AverageResponseTimes
        def initialize(ransack_query:, group_by: :group_by_day, route: nil)
          @ransack_query = ransack_query
          @group_by = group_by
          @route = route
        end

        def to_rails_chart
          requests = @ransack_query.result(distinct: false)
            .public_send(
              @group_by,
              "rails_pulse_requests.occurred_at",
              series: true,
              time_zone: "UTC"
            )
            .average("rails_pulse_requests.duration")

          requests.each_with_object({}) do |(period, average_duration), hash|
            occurred_at = period.is_a?(String) ? Time.parse(period) : period
            occurred_at = (occurred_at.is_a?(Time) || occurred_at.is_a?(Date)) ? occurred_at : Time.current

            normalized_occurred_at =
              case @group_by
              when :group_by_hour
                occurred_at&.beginning_of_hour || occurred_at
              when :group_by_day
                occurred_at&.beginning_of_day || occurred_at
              else
                occurred_at
              end
            hash[normalized_occurred_at.to_i] = {
              value: (average_duration || 0).to_f
            }
          end
        end
      end
    end
  end
end
