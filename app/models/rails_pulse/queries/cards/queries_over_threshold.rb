module RailsPulse
  module Queries
    module Cards
      class QueriesOverThreshold < RailsPulse::Cards::OverThresholdBase
        def initialize(query:, disabled_tags: [], show_non_tagged: true)
          super(subject: query, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged)
        end

        private

        def slo_config_key = :query_service_level_objectives
        def summarizable_type = "RailsPulse::Query"
        def base_card_id = "queries_over_threshold"
        def base_card_title = "Queries Over Threshold"
        def card_context = "queries"
      end
    end
  end
end
