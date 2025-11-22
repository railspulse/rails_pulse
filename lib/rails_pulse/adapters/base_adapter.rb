module RailsPulse
  module Adapters
    class BaseAdapter
      # Track a complete request with all operations
      # @param data [Hash] Complete request tracking data
      # @return [void]
      def track_request(data)
        raise NotImplementedError, "Subclasses must implement #track_request"
      end

      # Health check for adapter
      # @return [Boolean]
      def healthy?
        true
      end

      # Close any open connections (for cleanup)
      # @return [void]
      def close
        # No-op by default
      end
    end
  end
end
