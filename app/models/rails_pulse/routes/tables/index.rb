module RailsPulse
  module Routes
    module Tables
      class Index
        def initialize(ransack_query:, period_type: nil, start_time:, params:)
          @ransack_query = ransack_query
          @period_type = period_type
          @start_time = start_time
          @params = params
        end

        def to_table
          base_query = @ransack_query.result(distinct: false)
            .joins("INNER JOIN rails_pulse_routes ON rails_pulse_routes.id = rails_pulse_summaries.summarizable_id")
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: @period_type
            )

          base_query = base_query.where(summarizable_id: @route.id) if @route

          # Apply grouping and aggregation
          base_query
            .group(
              "rails_pulse_summaries.summarizable_id",
              "rails_pulse_summaries.summarizable_type",
              "rails_pulse_routes.id",
              "rails_pulse_routes.path",
              "rails_pulse_routes.method"
            )
            .select(
              "rails_pulse_summaries.summarizable_id",
              "rails_pulse_summaries.summarizable_type",
              "rails_pulse_routes.id as route_id",
              "rails_pulse_routes.path",
              "rails_pulse_routes.method as route_method",
              "AVG(rails_pulse_summaries.avg_duration) as avg_duration",
              "MAX(rails_pulse_summaries.max_duration) as max_duration",
              "SUM(rails_pulse_summaries.count) as count",
              "SUM(rails_pulse_summaries.error_count) as error_count",
              "SUM(rails_pulse_summaries.success_count) as success_count"
            )
        end
      end
    end
  end
end
