module RailsPulse
  module Subscribers
    class RequestSubscriber
      def self.subscribe!
        # Request tracking is now handled by RequestCollector middleware
        # This subscriber is disabled to avoid duplication
      end
    end
  end
end
