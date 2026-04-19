module RailsPulse
  module HasPerformanceStatus
    extend ActiveSupport::Concern

    class_methods do
      # Configure which attribute contains the duration value
      # @param attr [Symbol] The attribute name (e.g., :avg_duration, :duration)
      def performance_status_attribute(attr)
        @performance_status_attribute = attr
      end

      def get_performance_status_attribute
        @performance_status_attribute || :duration
      end
    end

    # Returns performance status based on configured thresholds
    # @return [Symbol] One of :fast, :slow, :very_slow, :critical
    def performance_status
      thresholds = RailsPulse.configuration.job_thresholds
      attr_name = self.class.get_performance_status_attribute
      duration_value = public_send(attr_name).to_f

      if duration_value < thresholds[:slow]
        :fast
      elsif duration_value < thresholds[:very_slow]
        :slow
      elsif duration_value < thresholds[:critical]
        :very_slow
      else
        :critical
      end
    end
  end
end
