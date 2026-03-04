module RailsPulse
  module Routes
    module Cards
      class RequestsOverThreshold < RailsPulse::Cards::OverThresholdBase
        def initialize(route:, disabled_tags: [], show_non_tagged: true)
          super(subject: route, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged)
        end

        private

        def slo_config_key = :service_level_objectives
        def summarizable_type = "RailsPulse::Route"
        def base_card_id = "requests_over_threshold"
        def base_card_title = "Requests Over Threshold"
        def card_context = "routes"
      end
    end
  end
end
