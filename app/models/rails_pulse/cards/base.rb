require "active_support/number_helper"

module RailsPulse
  module Cards
    class Base
      private

      def now
        @now ||= Time.current
      end

      def window_days
        @period || 7
      end

      def period_type_hours?
        @period_type == "hour"
      end

      # Enhanced time period helpers (support hour and day)
      def previous_window_start
        if period_type_hours?
          (now - (window_days * 48).hours).beginning_of_hour
        else
          (now - (window_days * 2).days).beginning_of_day
        end
      end

      def current_window_start
        if period_type_hours?
          (now - (window_days * 24).hours).beginning_of_hour
        else
          (now - window_days.days).beginning_of_day
        end
      end

      def range_start
        previous_window_start
      end

      # Base query helper for common summary query pattern
      def base_summary_query(summarizable_type)
        query = RailsPulse::Summary.where(
          summarizable_type: summarizable_type,
          period_type: @period_type || "day",
          period_start: range_start..now
        )

        # Apply tag filters if available
        if respond_to?(:disabled_tags, true) && respond_to?(:show_non_tagged, true)
          query = query.with_tag_filters(@disabled_tags, @show_non_tagged)
        end

        # Filter to specific resource if provided
        query = query.where(summarizable_id: subject_id) if subject_id

        query
      end

      def subject_id
        # Subclasses can override to provide @job.id, @query.id, @route.id
        instance_variable_get(:@job)&.id ||
          instance_variable_get(:@query)&.id ||
          instance_variable_get(:@route)&.id
      end

      def quote(time)
        RailsPulse::Summary.connection.quote(time)
      end

      # Enhanced sparkline generation (support hour and day)
      def sparkline_from(grouped_values)
        if period_type_hours?
          build_hourly_sparkline(grouped_values)
        else
          build_daily_sparkline(grouped_values)
        end
      end

      def build_hourly_sparkline(grouped_values)
        start_time = sparkline_start
        end_time = now.beginning_of_hour

        {}.tap do |hash|
          current_time = start_time
          while current_time <= end_time
            # Use timestamp in milliseconds for JS compatibility
            hash[current_time.to_i * 1000] = { value: grouped_values[current_time] || 0 }
            current_time += 1.hour
          end
        end
      end

      def build_daily_sparkline(grouped_values)
        start_date = sparkline_start.to_date
        end_date = now.to_date

        (start_date..end_date).each_with_object({}) do |day, hash|
          label = day.strftime("%b %-d")
          hash[label] = { value: grouped_values[day] || 0 }
        end
      end

      # Subclasses can override to customize sparkline start date
      # Default: show only current window (period days)
      # Override to range_start for full 2*period view
      def sparkline_start
        current_window_start
      end

      # Existing trend calculation (keep as-is)
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

      # Existing format helpers (keep as-is)
      def format_percentage(value, precision = 1)
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
