module RailsPulse
  module FormattingHelper
    def human_readable_occurred_at(occurred_at)
      return "" unless occurred_at.present?
      time = occurred_at.is_a?(String) ? Time.parse(occurred_at) : occurred_at
      time.strftime("%b %d, %Y %l:%M %p")
    end

    def time_ago_in_words(time)
      return "Unknown" if time.blank?

      # Convert to Time object if it's a string
      time = Time.parse(time.to_s) if time.is_a?(String)

      seconds_ago = Time.current - time

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
  end
end
