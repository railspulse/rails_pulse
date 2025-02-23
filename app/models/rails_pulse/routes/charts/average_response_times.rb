module RailsPulse
  module Routes
    module Charts
      class AverageResponseTimes
        def initialize(ransack_query:, group_by: :group_by_day, route: nil)
          @ransack_query = ransack_query
          @group_by = group_by
          @route = route
        end

        def to_rails_chart
          if @route
            # These are the requests for the specific route so it will just be a collection of Requests that we can
            # filter and sort using the attributes on each Request
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
            # These are the requests for all routes so we need to join the requests with the routes
            # and then group by the route
            requests = @ransack_query.result(distinct: false)
              .includes(:requests)
              .left_joins(:requests)
              .public_send(
                @group_by,
                "rails_pulse_requests.occurred_at",
                series: true
              )
              .select(
                "rails_pulse_requests.occurred_at",
                "COALESCE(AVG(rails_pulse_requests.duration), 0) AS average_response_time_ms"
              )

            requests.each_with_object({}) do |result, hash|
              occurred_at = result.occurred_at
              occurred_at = Time.parse(occurred_at) if occurred_at.is_a?(String)
              hash[occurred_at.to_i] = {
                value: result.average_response_time_ms.to_f
              }
            end
          end
        end
      end
    end
  end
end
