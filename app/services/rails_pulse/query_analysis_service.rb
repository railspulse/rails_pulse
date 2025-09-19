# Orchestrates comprehensive query analysis using modular analyzers.
# Coordinates multiple specialized analyzers and consolidates results into actionable insights.
module RailsPulse
  class QueryAnalysisService
    def self.analyze_query(query_id)
      query = RailsPulse::Query.find(query_id)
      new(query).analyze
    end

    def initialize(query)
      @query = query
      @operations = fetch_recent_operations
    end

    def analyze
      # Run all analyzers
      results = {
        analyzed_at: Time.current,
        query_characteristics: analyze_query_characteristics,
        index_recommendations: analyze_index_recommendations,
        n_plus_one_analysis: analyze_n_plus_one,
        explain_plan: analyze_explain_plan,
        backtrace_analysis: analyze_backtraces
      }

      # Generate consolidated suggestions
      results[:suggestions] = generate_suggestions(results)

      # Build compatible format for query model
      compatible_results = build_compatible_results(results)

      # Save results to query
      save_results_to_query(compatible_results)

      results
    end

    private

    def fetch_recent_operations
      @query.operations
            .where("occurred_at > ?", 48.hours.ago)
            .order(occurred_at: :desc)
            .limit(50)
    end

    def analyze_query_characteristics
      Analysis::QueryCharacteristicsAnalyzer.new(@query, @operations).analyze
    end

    def analyze_index_recommendations
      Analysis::IndexRecommendationEngine.new(@query, @operations).analyze
    end

    def analyze_n_plus_one
      Analysis::NPlusOneDetector.new(@query, @operations).analyze
    end

    def analyze_explain_plan
      return { explain_plan: nil, issues: [] } if @operations.empty?
      Analysis::ExplainPlanAnalyzer.new(@query, @operations).analyze
    end

    def analyze_backtraces
      return {} if @operations.empty?
      Analysis::BacktraceAnalyzer.new(@query, @operations).analyze
    end

    def generate_suggestions(analysis_results)
      Analysis::SuggestionGenerator.new(analysis_results).generate
    end

    # Build compatible format for query model storage
    def build_compatible_results(results)
      characteristics = results[:query_characteristics]
      explain_result = results[:explain_plan]

      {
        analyzed_at: results[:analyzed_at],
        explain_plan: explain_result[:explain_plan],
        issues: extract_all_issues(characteristics, explain_result),
        metadata: build_metadata(results),
        query_stats: extract_query_stats(characteristics),
        backtrace_analysis: results[:backtrace_analysis],
        index_recommendations: results[:index_recommendations],
        n_plus_one_analysis: results[:n_plus_one_analysis],
        suggestions: results[:suggestions]
      }
    end

    def extract_all_issues(characteristics, explain_result)
      issues = []
      issues.concat(characteristics[:pattern_issues] || [])
      issues.concat(explain_result[:issues] || [])
      issues
    end

    def extract_query_stats(characteristics)
      characteristics.except(:pattern_issues)
    end

    def build_metadata(results)
      {
        analyzers_used: results.keys.reject { |k| k.in?([ :analyzed_at, :suggestions ]) },
        analysis_version: "2.0",
        total_recommendations: results[:index_recommendations]&.count || 0,
        n_plus_one_detected: results.dig(:n_plus_one_analysis, :is_likely_n_plus_one) || false
      }
    end

    def save_results_to_query(results)
      @query.update!(
        analyzed_at: results[:analyzed_at],
        explain_plan: results[:explain_plan],
        issues: results[:issues],
        metadata: results[:metadata],
        query_stats: results[:query_stats],
        backtrace_analysis: results[:backtrace_analysis],
        index_recommendations: results[:index_recommendations],
        n_plus_one_analysis: results[:n_plus_one_analysis],
        suggestions: results[:suggestions]
      )
    end
  end
end
