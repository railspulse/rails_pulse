module RailsPulse
  class Configuration
    attr_accessor :enabled,
                  :route_thresholds,
                  :request_thresholds,
                  :query_thresholds,
                  :ignored_routes,
                  :ignored_requests,
                  :ignored_queries,
                  :full_retention_period,
                  :max_database_size_mb,
                  :metric_cache_enabled,
                  :metric_cache_duration

    def initialize
      @enabled = true
      @route_thresholds = { slow: 500, very_slow: 1500, critical: 3000 }
      @request_thresholds = { slow: 700, very_slow: 2000, critical: 4000 }
      @query_thresholds = { slow: 100, very_slow: 500, critical: 1000 }
      @ignored_routes = []
      @ignored_requests = []
      @ignored_queries = []
      @full_retention_period = 2.days
      @max_database_size_mb = nil
      @metric_cache_enabled = true
      @metric_cache_duration = 1.day
    end
  end
end
