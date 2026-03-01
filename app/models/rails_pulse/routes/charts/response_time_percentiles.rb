module RailsPulse
  module Routes
    module Charts
      class ResponseTimePercentiles < RailsPulse::Charts::PercentileChartBase
        def initialize(route: nil, **kwargs)
          super(subject: route, **kwargs)
        end

        private

        def summarizable_type = "RailsPulse::Route"
        def slo_config_key = :service_level_objective
      end
    end
  end
end
