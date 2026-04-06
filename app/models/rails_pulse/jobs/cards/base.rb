require "active_support/number_helper"

module RailsPulse
  module Jobs
    module Cards
      class Base
        private

        def now
          @now ||= Time.current
        end

        def window_days
          @period || 7
        end

        def previous_window_start
          (now - (window_days * 2).days).beginning_of_day
        end

        def current_window_start
          (now - window_days.days).beginning_of_day
        end

        def range_start
          previous_window_start
        end

        def quote(time)
          RailsPulse::Summary.connection.quote(time)
        end

        def sparkline_from(grouped_values)
          start_date = current_window_start.to_date
          end_date = now.to_date

          (start_date..end_date).each_with_object({}) do |day, hash|
            label = day.strftime("%b %-d")
            hash[label] = { value: grouped_values[day] || 0 }
          end
        end

        def trend_for(current_value, previous_value, precision: 1)
          percentage = previous_value.zero? ? 0.0 : ((current_value - previous_value) / previous_value.to_f * 100).round(precision)

          icon = if percentage.abs < 0.1
            "move-right"
          elsif percentage.positive?
            "trending-up"
          else
            "trending-down"
          end

          [ icon, format_percentage(percentage.abs, precision) ]
        end

        def format_percentage(value, precision)
          "#{value.round(precision)}%"
        end

        def format_number(value)
          ActiveSupport::NumberHelper.number_to_delimited(value)
        end

        def format_duration(value)
          "#{value.round(0)} ms"
        end
      end
    end
  end
end
