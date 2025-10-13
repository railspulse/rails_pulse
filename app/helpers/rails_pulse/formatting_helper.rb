module RailsPulse
  module FormattingHelper
    def human_readable_occurred_at(occurred_at)
      return "" unless occurred_at.present?
      time = occurred_at.is_a?(String) ? Time.parse(occurred_at) : occurred_at
      # Convert to local system timezone (same as charts use)
      time.getlocal.strftime("%b %d, %Y %l:%M %p")
    end

    def time_ago_in_words(time)
      return "Unknown" if time.blank?

      # Convert to Time object if it's a string
      time = Time.parse(time.to_s) if time.is_a?(String)
      # Convert to local system timezone for consistent calculation
      time = time.getlocal

      seconds_ago = Time.now - time

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

    def human_readable_summary_period(summary)
      return "" unless summary&.period_start&.present? && summary&.period_end&.present?

      # Convert UTC times to local system timezone to match chart display
      start_time = summary.period_start.getlocal
      end_time = summary.period_end.getlocal


      case summary.period_type
      when "hour"
        start_time.strftime("%b %e %Y, %l:%M %p") + " - " + end_time.strftime("%l:%M %p")
      when "day"
        start_time.strftime("%b %e, %Y")
      end
    end
  end
end
