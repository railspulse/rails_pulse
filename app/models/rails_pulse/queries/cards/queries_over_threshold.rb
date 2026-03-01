module RailsPulse
  module Queries
    module Cards
      class QueriesOverThreshold < RailsPulse::Cards::OverThresholdBase
        def initialize(query:, disabled_tags: [], show_non_tagged: true)
          super(subject: query, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged)
        end

        private

        def slo_config_key = :query_service_level_objective
        def summarizable_type = "RailsPulse::Query"
        def card_id = "queries_over_threshold"
        def card_context = "queries"
        def card_title = "Queries Over Threshold"
      end
    end
  end
end
