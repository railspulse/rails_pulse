module RailsPulse
  module Suggestions
    class CacheSuggestionsService < Base
      def generate
        suggestions = []

        if operation.operation_type == "cache_read" && operation.duration > 10
          suggestions << build_suggestion(
            type: "performance",
            icon: "clock",
            title: "Slow Cache Read",
            description: "Cache read took #{operation.duration.round(2)}ms. Check cache backend performance.",
            priority: "medium"
          )
        end

        suggestions
      end
    end
  end
end
