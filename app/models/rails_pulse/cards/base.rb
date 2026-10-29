require "active_support/number_helper"

module RailsPulse
  module Cards
    class Base
      def initialize(window: nil, subject: nil, period: 7, period_type: "day", disabled_tags: [], show_non_tagged: true)
        @window = window
        @subject = subject
        @period = period
        @period_type = period_type
        @disabled_tags = disabled_tags
        @show_non_tagged = show_non_tagged
      end

      private

      # nil unless the caller passed a window, so the "trailing @period
      # days/hours" fallback below still applies by default.
      def time_window
        @window
      end

      def now
        @now ||= time_window&.end_time || Time.current
      end

      def window_days
        time_window&.days || @period || 7
      end

      def period_type_hours?
        @period_type == "hour"
      end

      # Enhanced time period helpers (support hour and day)
      def previous_window_start
        if time_window
          time_window.previous(period_type_hours? ? "hour" : "day").start_time
        elsif period_type_hours?
          (now - (window_days * 48).hours).beginning_of_hour
        else
          (now - (window_days * 2).days).beginning_of_day
        end
      end

      def current_window_start
        if time_window
          time_window.start_time
        elsif period_type_hours?
          (now - (window_days * 24).hours).beginning_of_hour
        else
          (now - window_days.days).beginning_of_day
        end
      end

      # Length of the current window, for turning its count into a rate. The
      # previous window is only there for the trend, so it is not counted.
      def current_window_minutes
        [ (now - current_window_start) / 1.minute, 1 ].max
      end

      # "12.5 / min", falling back to per hour then per day so low volumes
      # do not read as zero.
      def format_rate(count, minutes)
        per_minute = count.to_f / minutes

        if per_minute >= 1
          "#{per_minute.round(2)} / min"
        elsif per_minute * 60 >= 1
          "#{(per_minute * 60).round(2)} / hour"
        else
          "#{(per_minute * 60 * 24).round(2)} / day"
        end
      end

      def show_trend?
        window_days <= 14
      end

      def range_start
        show_trend? ? previous_window_start : current_window_start
      end

      # Base query helper for common summary query pattern.
      #
      # When the trend is shown the range also spans the previous window, so
      # headline values must come from the :current_start CASE WHEN aggregates
      # (window_sql), never a plain SUM over the whole relation.
      def base_summary_query(summarizable_type)
        query = RailsPulse::Summary.where(
          summarizable_type: summarizable_type,
          period_type: @period_type || "day",
          period_start: range_start..now
        )

        # The same tag filter the sparkline applies, so the headline number and
        # the sparkline beside it are computed over the same summaries. Cards
        # receive the filter as instance variables; nil means unfiltered.
        query = query.with_tag_filters(@disabled_tags || [], @show_non_tagged != false)

        # Filter to specific resource if provided
        query = query.where(summarizable_id: subject_id) if subject_id

        query
      end

      def subject_id
        @subject&.id
      end

      # A SELECT fragment comparing against the card's window, with the
      # bounds bound as values (:current_start, :range_start) rather than
      # interpolated into the SQL string.
      def window_sql(fragment)
        Arel.sql(
          RailsPulse::Summary.sanitize_sql_array([ fragment, { current_start: current_window_start, range_start: range_start } ])
        )
      end

      # Enhanced sparkline generation (support hour and day)
      #
      # ghost_incomplete: an absent value in a still-running period means
      # "not summarized yet", not zero; live-sourced cards pass false.
      def sparkline_from(grouped_values, ghost_incomplete: true, &decorate)
        if period_type_hours?
          build_hourly_sparkline(grouped_values, ghost_incomplete: ghost_incomplete, &decorate)
        else
          build_daily_sparkline(grouped_values, ghost_incomplete: ghost_incomplete, &decorate)
        end
      end

      def build_hourly_sparkline(grouped_values, ghost_incomplete: true, &decorate)
        ghost_height = ghost_height_for(grouped_values)
        sparkline_hours.each_with_object({}) do |current_time, hash|
          value = grouped_values[current_time]
          # Use timestamp in milliseconds for JS compatibility
          hash[current_time.to_i * 1000] = if ghost_incomplete && value.nil? && incomplete_period?(current_time)
            ghost_bucket(ghost_height)
          else
            sparkline_bucket(value, &decorate)
          end
        end
      end

      def build_daily_sparkline(grouped_values, ghost_incomplete: true, &decorate)
        ghost_height = ghost_height_for(grouped_values)
        sparkline_dates.each_with_object({}) do |day, hash|
          value = grouped_values[day]
          hash[day.strftime("%b %-d")] = if ghost_incomplete && value.nil? && incomplete_period?(day)
            ghost_bucket(ghost_height)
          else
            sparkline_bucket(value, &decorate)
          end
        end
      end

      def sparkline_bucket(value, &decorate)
        bucket = { value: value || 0 }
        decorate ? decorate.call(bucket) : bucket
      end

      # A summary cannot exist until its period has ended.
      def incomplete_period?(bucket_start)
        if bucket_start.is_a?(Date)
          bucket_start >= Time.current.to_date
        else
          bucket_start + 1.hour > Time.current
        end
      end

      # chart_controller.js draws the slot as a dashed outline whose height
      # carries no meaning, with incompleteLabel as the tooltip.
      def ghost_bucket(height)
        {
          value: height,
          incomplete: true,
          incompleteLabel: "#{period_type_hours? ? "Hour" : "Day"} in progress"
        }
      end

      def ghost_height_for(grouped_values)
        grouped_values.values.compact.max || 0
      end

      # Subclasses can override to customize sparkline start date
      # Default: show only current window (period days)
      # Override to range_start for full 2*period view
      def sparkline_start
        current_window_start
      end

      # Every calendar date in the sparkline window. Via TimeWindow, so a
      # range not starting on a day boundary skips the leading partial day.
      def sparkline_dates
        time_window&.dates || (sparkline_start.to_date..now.to_date).to_a
      end

      # Same skip-partial semantics as sparkline_dates, for hours.
      def sparkline_hours
        time_window&.hour_starts || begin
          start_time = sparkline_start.beginning_of_hour
          end_time = now.beginning_of_hour
          hours = []
          current_time = start_time
          while current_time <= end_time
            hours << current_time
            current_time += 1.hour
          end
          hours
        end
      end

      # Build sparkline query with tag filters and optional subject filter
      def build_sparkline_query(summarizable_type)
        sparkline_query = RailsPulse::Summary
          .with_tag_filters(@disabled_tags, @show_non_tagged)
          .where(
            summarizable_type: summarizable_type,
            period_type: @period_type,
            period_start: current_window_start..now
          )
        sparkline_query = sparkline_query.where(summarizable_id: subject_id) if subject_id
        sparkline_query
      end

      # Group sparkline query by period type (hour or day)
      def group_sparkline_by_period(sparkline_query, sum_field)
        bucket_by_period(sparkline_query) { |relation| relation.sum(sum_field) }
      end

      # Aggregates `relation` per calendar day of Time.zone, or per hour when
      # the card's period type is "hour". The block receives the relation
      # grouped by `column` and does the arithmetic in SQL; only the
      # re-bucketing of keys happens here. It is done in Ruby because SQL
      # DATE() / DATE_TRUNC() operate on the stored UTC value, which puts a
      # Melbourne midnight on the previous calendar date and a Kolkata hour
      # thirty minutes off, so the sparkline lookups (keyed by Time.zone
      # dates and hour starts) would miss.
      def bucket_by_period(relation, column: :period_start)
        yield(relation.group(column)).each_with_object({}) do |(time, value), buckets|
          next if time.nil? || value.nil?

          local = time.in_time_zone
          key = period_type_hours? ? local.beginning_of_hour : local.to_date
          buckets[key] = (buckets[key] || 0) + value
        end
      end

      def period_date_range
        start_date = sparkline_dates.first || current_window_start.to_date
        end_date = now.to_date
        if start_date.year == end_date.year
          "#{start_date.strftime("%b %-d")} – #{end_date.strftime("%b %-d")}"
        else
          "#{start_date.strftime("%b %-d, %Y")} – #{end_date.strftime("%b %-d, %Y")}"
        end
      end

      def comparison_period_text
        if period_type_hours?
          "Compared to previous 24 hours"
        else
          case window_days
          when 1  then "Compared to previous day"
          when 7  then "Compared to previous 7 days"
          when 14 then "Compared to previous 14 days"
          when 30 then "Compared to previous 30 days"
          else         "Compared to previous #{window_days} days"
          end
        end
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

      # Compares a subject against its own history rather than against the
      # immediately preceding window.
      #
      # The period-over-period arrow above answers "is this week worse than last
      # week?", which is noisy — last week may itself have been unusual. This
      # answers "is this worse than how this normally behaves?", which is the
      # question the number is actually being read for.
      #
      # Only available where there is a single subject to have a history. Index
      # pages aggregate across every route or query, so they keep the
      # period-over-period arrow.
      #
      # @return [Array(String, String, String), nil] icon, amount, caption
      def baseline_trend_for(subject, metric:)
        return nil if subject.nil?

        comparison = RailsPulse::Operations::Compare.call(subject, metric: metric)
        return nil unless comparison.sufficient_data?

        percentage = comparison.percent_change

        icon = if percentage.abs < 0.1
          "move-right"
        elsif percentage.positive?
          "trending-up"
        else
          "trending-down"
        end

        [ icon, format_percentage(percentage.abs, 1), baseline_caption(comparison) ]
      end

      # Names the change point only when there is a regression to explain. On a
      # healthy metric "since Aug 26" would be noise, and locating it costs a
      # second query that is not worth spending to say nothing.
      def baseline_caption(comparison)
        caption = "Compared to its #{baseline_window_text} normal"
        return caption unless comparison.regression?

        change_point = RailsPulse::Operations::ChangePoint.call(
          comparison.subject, metric: comparison.metric
        )
        return caption if change_point.nil?

        stamp = change_point.hourly? ? change_point.at.strftime("%b %-d %H:%M") : change_point.at.strftime("%b %-d")
        "#{caption} · since #{stamp}"
      end

      def baseline_window_text
        days = (RailsPulse.configuration.baseline_window / 1.day).round
        "#{days}-day"
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
