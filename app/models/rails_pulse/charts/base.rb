module RailsPulse
  module Charts
    class Base
      def initialize(ransack_query:, period_type: nil, subject: nil, window: nil, start_duration: nil, disabled_tags: [], show_non_tagged: true)
        @ransack_query = ransack_query
        @period_type = period_type
        @subject = subject
        @window = window
        @start_duration = start_duration
        @disabled_tags = disabled_tags
        @show_non_tagged = show_non_tagged
      end

      private

      # Common helper for building base summary queries with tag filters
      def base_summary_query
        @ransack_query.result(distinct: false)
          .with_tag_filters(@disabled_tags, @show_non_tagged)
          .where(
            summarizable_type: summarizable_type,
            period_type: @period_type
          )
          .then { |q| @subject ? q.where(summarizable_id: @subject.id) : q }
      end

      # Abstract method - must be implemented by subclasses
      def summarizable_type
        raise NotImplementedError, "#{self.class} must implement summarizable_type"
      end

      # Every bucket in the window, with zero where there is no data.
      def pad_data_with_zeros(raw_data)
        @window.bucket_timestamps(@period_type).index_with { |timestamp| raw_data[timestamp] || 0 }
      end
    end
  end
end
