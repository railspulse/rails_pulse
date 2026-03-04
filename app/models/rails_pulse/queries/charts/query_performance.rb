module RailsPulse
  module Queries
    module Charts
      class QueryPerformance < RailsPulse::Charts::PercentileChartBase
        def initialize(query: nil, **kwargs)
          super(subject: query, **kwargs)
        end

        private

        def summarizable_type = "RailsPulse::Query"
        def slo_config_key = :query_service_level_objectives
      end
    end
  end
end
