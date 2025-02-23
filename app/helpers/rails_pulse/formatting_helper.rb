module RailsPulse
  module FormattingHelper
    def human_readable_occurred_at(occurred_at)
      return "" unless occurred_at.present?
      time = occurred_at.is_a?(String) ? Time.parse(occurred_at) : occurred_at
      time.strftime("%b %d, %Y %l:%M %p")
    end
  end
end
