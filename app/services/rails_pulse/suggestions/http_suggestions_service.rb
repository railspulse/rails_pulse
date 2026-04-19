module RailsPulse
  module Suggestions
    class HttpSuggestionsService < Base
      def generate
        suggestions = []

        if operation.duration > 1000
          suggestions << build_suggestion(
            type: "performance",
            icon: "globe",
            title: "Slow External Request",
            description: "HTTP request took #{operation.duration.round(2)}ms. Consider caching responses or using background jobs.",
            priority: "high"
          )
        end

        suggestions
      end
    end
  end
end
