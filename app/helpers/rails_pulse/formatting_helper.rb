module RailsPulse
  module FormattingHelper
    def human_readable_occurred_at(occurred_at)
      return "" unless occurred_at.present?
      # Time.zone, not the server's OS zone — the same zone charts label as
      # the aggregation zone, so this and the charts always agree.
      time = occurred_at.is_a?(String) ? Time.zone.parse(occurred_at) : occurred_at
      return "" if time.nil?
      time.strftime("%b %d, %Y %l:%M %p")
    end

    # "Nov 3, 12:00 – Nov 6, 12:00" for the time-range selector. The year is
    # shown only when the range is not in the current year, to keep the label
    # short enough for a phone's top bar. Values that do not parse are shown
    # as they were stored.
    def custom_time_range_label(start_time, end_time)
      times = [ start_time, end_time ].map { |value| Time.zone.parse(value.to_s) }
      return "#{start_time} to #{end_time}" if times.any?(&:nil?)

      format = times.all? { |time| time.year == Time.current.year } ? "%b %-d, %H:%M" : "%b %-d %Y, %H:%M"
      times.map { |time| time.strftime(format) }.join(" – ")
    rescue ArgumentError
      "#{start_time} to #{end_time}"
    end

    def time_ago_in_words(time)
      return "Unknown" if time.blank?

      time = Time.zone.parse(time.to_s) if time.is_a?(String)

      seconds_ago = [ Time.current - time, 0 ].max

      case seconds_ago
      when 0..59
        "#{seconds_ago.to_i}s ago"
      when 60..3599
        "#{(seconds_ago / 60).to_i}m ago"
      when 3600..86399
        "#{(seconds_ago / 3600).to_i}h ago"
      else
        "#{(seconds_ago / 86400).to_i}d ago"
      end
    end

    def human_readable_bytes(value)
      return "—" if value.nil?
      number_to_human_size(value, precision: 2)
    end

    def human_readable_summary_period(summary)
      return "" unless summary&.period_start&.present? && summary&.period_end&.present?

      # Already Time.zone-aware from ActiveRecord — the same aggregation
      # zone charts label, so no conversion needed.
      start_time = summary.period_start
      end_time = summary.period_end

      case summary.period_type
      when "hour"
        start_time.strftime("%b %e %Y, %l:%M %p") + " - " + end_time.strftime("%l:%M %p")
      when "day"
        start_time.strftime("%b %e, %Y")
      end
    end
  end
end
