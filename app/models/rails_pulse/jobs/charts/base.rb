module RailsPulse
  module Jobs
    module Charts
      class Base
        def initialize(ransack_query:, period_type: nil, job: nil, start_time: nil, end_time: nil, start_duration: nil, disabled_tags: [], show_non_tagged: true)
          @ransack_query = ransack_query
          @period_type = period_type
          @job = job
          @start_time = start_time
          @end_time = end_time
          @start_duration = start_duration  # Currently unused, kept for API compatibility
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        private

        # Common helper for building base summary queries with tag filters
        def base_summary_query
          @ransack_query.result(distinct: false)
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Job",
              period_type: @period_type
            )
            .then { |q| @job ? q.where(summarizable_id: @job.id) : q }
        end

        # Common helper for time step calculation
        def time_step
          @period_type.to_s == "hour" ? 3600 : 86400
        end
      end
    end
  end
end
