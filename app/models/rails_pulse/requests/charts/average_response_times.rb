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
          # Get actual data using existing logic
          actual_data = @ransack_query.result(distinct: false)
            .public_send(
              @group_by,
              "rails_pulse_requests.occurred_at",
              series: true,
              time_zone: "UTC"
            )
            .average("rails_pulse_requests.duration")

          # Create full time range and fill in missing periods
          fill_missing_periods(actual_data)
        end

        private

        def fill_missing_periods(actual_data)
          # Extract actual time range from ransack query conditions
          start_time, end_time = extract_time_range_from_ransack

          # Create time range based on grouping type
          case @group_by
          when :group_by_hour
            time_range = generate_hour_range(start_time, end_time)
          else # :group_by_day
            time_range = generate_day_range(start_time, end_time)
          end

          # Fill in all periods with zero values for missing periods
          time_range.each_with_object({}) do |period, result|
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

            # Use actual data if available, otherwise default to 0
            average_duration = actual_data[period] || 0
            result[normalized_occurred_at.to_i] = {
              value: average_duration.to_f
            }
          end
        end

        def generate_day_range(start_time, end_time)
          (start_time.to_date..end_time.to_date).map(&:beginning_of_day)
        end

        def generate_hour_range(start_time, end_time)
          current = start_time
          hours = []
          while current <= end_time
            hours << current
            current += 1.hour
          end
          hours
        end

        def extract_time_range_from_ransack
          # Extract time range from ransack conditions
          conditions = @ransack_query.conditions

          # For requests, look for occurred_at conditions on rails_pulse_requests
          start_condition = conditions.find { |c| c.a.first == "rails_pulse_requests_occurred_at" && c.p == "gteq" }
          end_condition = conditions.find { |c| c.a.first == "rails_pulse_requests_occurred_at" && c.p == "lt" }

          start_time = start_condition&.v || 2.weeks.ago
          end_time = end_condition&.v || Time.current

          # Normalize time boundaries based on grouping
          case @group_by
          when :group_by_hour
            [ start_time.beginning_of_hour, end_time.beginning_of_hour ]
          else
            [ start_time.beginning_of_day, end_time.beginning_of_day ]
          end
        end
      end
    end
  end
end
