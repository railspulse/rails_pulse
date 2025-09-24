# Detects N+1 query patterns by analyzing query repetition within request cycles.
# Groups operations by time windows and identifies repetitive single-record lookups that suggest missing eager loading.
module RailsPulse
  module Analysis
    class NPlusOneDetector < BaseAnalyzer
      REQUEST_GROUPING_WINDOW = 0.1.seconds
      REPETITION_THRESHOLD = 3

      def analyze
        return default_result if operations.empty?

        analysis = {
          is_likely_n_plus_one: false,
          confidence_score: 0,
          evidence: [],
          suggested_fixes: [],
          execution_patterns: {}
        }

        # Group operations by request cycles
        request_groups = group_operations_by_request

        # Analyze patterns within each request
        request_groups.each do |group|
          pattern_analysis = analyze_request_pattern(group)

          if pattern_analysis[:repetitive_queries]
            analysis[:is_likely_n_plus_one] = true
            analysis[:confidence_score] += pattern_analysis[:confidence]
            analysis[:evidence].concat(pattern_analysis[:evidence])
            analysis[:suggested_fixes].concat(pattern_analysis[:fixes])
          end
        end

        # Normalize confidence score
        analysis[:confidence_score] = [ analysis[:confidence_score], 100 ].min

        # Add execution pattern analysis
        analysis[:execution_patterns] = analyze_execution_patterns

        # Generate ActiveRecord-specific suggestions
        if analysis[:is_likely_n_plus_one]
          analysis[:suggested_fixes].concat(generate_activerecord_fixes)
        end

        analysis
      end

      private

      def default_result
        {
          is_likely_n_plus_one: false,
          confidence_score: 0,
          evidence: [],
          suggested_fixes: [],
          execution_patterns: {}
        }
      end

      def group_operations_by_request
        groups = []
        current_group = []

        sorted_operations = operations.sort_by(&:occurred_at)

        sorted_operations.each do |operation|
          if current_group.empty? || time_within_window?(operation, current_group.last)
            current_group << operation
          else
            groups << current_group if current_group.size > 1
            current_group = [ operation ]
          end
        end

        groups << current_group if current_group.size > 1
        groups
      end

      def time_within_window?(operation, last_operation)
        (operation.occurred_at - last_operation.occurred_at) < REQUEST_GROUPING_WINDOW
      end

      def analyze_request_pattern(operations_group)
        analysis = {
          repetitive_queries: false,
          confidence: 0,
          evidence: [],
          fixes: []
        }

        # Look for repeated similar queries
        normalized_queries = operations_group.map { |op| normalize_sql_for_pattern_detection(op.label) }
        query_counts = normalized_queries.tally

        query_counts.each do |normalized_query, count|
          next unless count >= REPETITION_THRESHOLD

          analysis[:repetitive_queries] = true
          analysis[:confidence] += count * 10 # Higher repetition = higher confidence

          analysis[:evidence] << {
            type: "repetitive_query",
            description: "Query executed #{count} times in single request",
            query_pattern: normalized_query,
            occurrences: count
          }

          # Detect specific N+1 patterns
          if single_record_lookup_pattern?(normalized_query)
            analysis[:evidence] << {
              type: "single_record_lookup",
              description: "Single record lookup pattern suggests missing eager loading",
              query_pattern: normalized_query
            }

            analysis[:fixes] << {
              type: "eager_loading",
              description: "Use includes() or preload() to load associated records",
              code_example: detect_association_from_query(normalized_query)
            }
          end
        end

        analysis
      end

      def single_record_lookup_pattern?(normalized_query)
        normalized_query.match?(/SELECT.*FROM.*WHERE.*=\s*\?/i)
      end

      def analyze_execution_patterns
        return {} if operations.empty?

        {
          total_executions: operations.count,
          time_span_minutes: time_span_in_minutes,
          executions_per_minute: calculate_executions_per_minute,
          peak_execution_periods: find_peak_execution_periods,
          common_execution_contexts: extract_execution_contexts
        }
      end

      def time_span_in_minutes
        return 0 if operations.count < 2
        ((operations.last.occurred_at - operations.first.occurred_at) / 1.minute).round(2)
      end

      def calculate_executions_per_minute
        return 0 if operations.count < 2

        time_span = operations.last.occurred_at - operations.first.occurred_at
        return operations.count if time_span <= 0

        (operations.count / (time_span / 1.minute)).round(2)
      end

      def find_peak_execution_periods
        # Group by 5-minute windows and find peaks
        windows = operations.group_by { |op| (op.occurred_at.to_i / 300) * 300 }
        return [] if windows.empty?

        avg_per_window = windows.values.sum(&:count).to_f / windows.count

        windows.select { |_, ops| ops.count > avg_per_window * 1.5 }.map do |timestamp, ops|
          {
            period: Time.at(timestamp).strftime("%Y-%m-%d %H:%M"),
            executions: ops.count,
            above_average_by: ((ops.count - avg_per_window) / avg_per_window * 100).round(1)
          }
        end
      end

      def extract_execution_contexts
        contexts = operations.filter_map(&:codebase_location).compact
        return {} if contexts.empty?

        # Extract controller/model patterns
        controller_actions = extract_controller_actions(contexts)
        model_methods = extract_model_methods(contexts)

        {
          controller_actions: controller_actions.tally,
          model_methods: model_methods.tally,
          unique_locations: contexts.uniq.count,
          total_contexts: contexts.count
        }
      end

      def extract_controller_actions(contexts)
        contexts.filter_map do |context|
          match = context.match(%r{app/controllers/(.+?)#(.+)})
          "#{match[1]}##{match[2]}" if match
        end
      end

      def extract_model_methods(contexts)
        contexts.filter_map do |context|
          match = context.match(%r{app/models/(.+?)\.rb.*in `(.+?)'})
          "#{match[1]}.#{match[2]}" if match
        end
      end

      def generate_activerecord_fixes
        [
          {
            type: "includes",
            description: "Use includes() to eager load associations",
            code_example: "User.includes(:posts).where(active: true)"
          },
          {
            type: "preload",
            description: "Use preload() when you don't need to query on associations",
            code_example: "User.preload(:posts).limit(10)"
          },
          {
            type: "joins",
            description: "Use joins() when you only need to filter, not access associated data",
            code_example: "User.joins(:posts).where(posts: { published: true })"
          }
        ]
      end

      def detect_association_from_query(normalized_query)
        # Try to extract table/column info to suggest specific associations
        match = normalized_query.match(/from\s+(\w+).*where\s+(\w+)\s*=/)
        return "Model.includes(:association)" unless match

        table = match[1]
        column = match[2]

        if column.end_with?("_id")
          association = column.gsub("_id", "")
          return "#{table.classify}.includes(:#{association})"
        end

        "Model.includes(:association)"
      end
    end
  end
end
