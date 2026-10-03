module RailsPulse
  # Suggests retuning route_thresholds and query_thresholds when one summary
  # period shows them to be out of step with the application: a slow
  # threshold most of the slowest routes or queries exceed only adds noise,
  # and a critical threshold nothing came within half of will never fire.
  #
  # Reads the period's ten slowest routes (by P95) and ten most expensive
  # queries (by total time). Each recommendation carries a config_snippet
  # that keeps the threshold keys it does not change.
  class ConfigRecommendations
    SAMPLE_SIZE = 10

    def self.for_period(period_type:, period_start:)
      period = RailsPulse::Summary.where(period_type: period_type, period_start: period_start)

      route_rows = period.for_routes.order(p95_duration: :desc).limit(SAMPLE_SIZE).map do |summary|
        { route_id: summary.summarizable_id, p95_duration: summary.p95_duration&.round(0) }
      end
      query_rows = period.for_queries.order(Arel.sql("rails_pulse_summaries.count * rails_pulse_summaries.avg_duration DESC")).limit(SAMPLE_SIZE).map do |summary|
        { query_id: summary.summarizable_id, p95_duration: summary.p95_duration&.round(0) }
      end

      new(route_rows: route_rows, query_rows: query_rows)
    end

    def initialize(route_rows:, query_rows:)
      @route_rows       = route_rows
      @query_rows       = query_rows
      @route_thresholds = RailsPulse.configuration.route_thresholds
      @query_thresholds = RailsPulse.configuration.query_thresholds
    end

    def to_recommendations
      route_recommendations + query_recommendations
    end

    private

    def route_recommendations
      return [] if @route_rows.size < 3

      slow     = @route_thresholds[:slow].to_i
      critical = @route_thresholds[:critical].to_i
      p95s     = @route_rows.map { |r| r[:p95_duration].to_i }
      above_slow = p95s.count { |p| p >= slow }
      max_p95    = p95s.max.to_i
      recs       = []

      if above_slow >= 3 && above_slow.to_f / @route_rows.size >= 0.4
        suggested = ceil_to(slow * 1.5, 50)
        recs << {
          title:          "Route slow threshold may be too low",
          detail:         "#{above_slow} of #{@route_rows.size} sampled routes exceeded the #{slow}ms slow " \
                          "threshold this period, which may generate more noise than signal in " \
                          "the Needs Attention section.",
          config_snippet: snippet("route_thresholds", @route_thresholds, slow: suggested)
        }
      end

      if max_p95 > 0 && max_p95 < critical / 2
        suggested = [ ceil_to(max_p95 * 2.0, 500), slow * 3, @route_thresholds[:very_slow].to_i ].max
        recs << {
          title:          "Route critical threshold may be too permissive",
          detail:         "No route came close to the #{critical}ms critical threshold this period " \
                          "(highest P95: #{max_p95}ms). Lowering it helps surface real regressions " \
                          "before they become user-visible.",
          config_snippet: snippet("route_thresholds", @route_thresholds, critical: suggested)
        }
      end

      recs
    end

    def query_recommendations
      return [] if @query_rows.size < 3

      slow     = @query_thresholds[:slow].to_i
      critical = @query_thresholds[:critical].to_i
      p95s     = @query_rows.map { |r| r[:p95_duration].to_i }
      above_slow = p95s.count { |p| p >= slow }
      max_p95    = p95s.max.to_i
      recs       = []

      if above_slow >= 3 && above_slow.to_f / @query_rows.size >= 0.4
        suggested = ceil_to(slow * 1.5, 10)
        recs << {
          title:          "Query slow threshold may be too low",
          detail:         "#{above_slow} of #{@query_rows.size} sampled queries exceeded the #{slow}ms slow " \
                          "threshold this period.",
          config_snippet: snippet("query_thresholds", @query_thresholds, slow: suggested)
        }
      end

      if max_p95 > 0 && max_p95 < critical / 2
        suggested = [ ceil_to(max_p95 * 2.0, 100), slow * 3, @query_thresholds[:very_slow].to_i ].max
        recs << {
          title:          "Query critical threshold may be too permissive",
          detail:         "No query came close to the #{critical}ms critical threshold this period " \
                          "(highest P95: #{max_p95}ms).",
          config_snippet: snippet("query_thresholds", @query_thresholds, critical: suggested)
        }
      end

      recs
    end

    # The whole hash, so pasting the line does not drop very_slow.
    def snippet(setting, current, **changes)
      pairs = current.merge(changes).map { |key, value| "#{key}: #{value}" }
      "config.#{setting} = { #{pairs.join(', ')} }"
    end

    # Round value up to the nearest multiple of step.
    def ceil_to(value, step)
      (value.to_f / step).ceil * step
    end
  end
end
