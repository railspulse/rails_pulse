module RailsPulse
  module Suggestions
    class ControllerSuggestionsService < Base
      def generate
        suggestions = []

        if operation.duration > 500
          suggestions << build_suggestion(
            type: "performance",
            icon: "zap",
            title: "Slow Controller Action",
            description: "This action took #{operation.duration.round(2)}ms. Consider moving heavy computation to background jobs.",
            priority: "high"
          )
        end

        suggestions
      end
    end
  end
end
