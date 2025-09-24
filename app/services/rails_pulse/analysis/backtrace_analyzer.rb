# Analyzes execution backtraces to identify code hotspots and execution patterns.
# Tracks most common execution locations, controller/model usage, and framework layer distribution.
module RailsPulse
  module Analysis
    class BacktraceAnalyzer < BaseAnalyzer
      def analyze
        backtraces = extract_backtraces

        {
          total_executions: operations.count,
          unique_locations: backtraces.uniq.count,
          most_common_location: find_most_common_location(backtraces),
          potential_n_plus_one: detect_simple_n_plus_one_pattern,
          execution_frequency: calculate_execution_frequency,
          location_distribution: calculate_location_distribution(backtraces),
          code_hotspots: identify_code_hotspots(backtraces),
          execution_contexts: analyze_execution_contexts(backtraces)
        }
      end

      private

      def extract_backtraces
        operations.filter_map(&:codebase_location).compact
      end

      def find_most_common_location(backtraces)
        return nil if backtraces.empty?

        frequency = backtraces.tally
        most_common = frequency.max_by { |_, count| count }

        return nil unless most_common

        {
          location: most_common[0],
          count: most_common[1],
          percentage: (most_common[1].to_f / backtraces.length * 100).round(1)
        }
      end

      def detect_simple_n_plus_one_pattern
        # Simple N+1 detection: many operations with same query in short time
        time_window = 1.minute
        groups = operations.group_by { |op| op.occurred_at.beginning_of_minute }

        suspicious_groups = groups.select { |_, ops| ops.count > 10 }

        {
          detected: suspicious_groups.any?,
          suspicious_periods: suspicious_groups.map do |time, ops|
            {
              period: time.strftime("%Y-%m-%d %H:%M"),
              count: ops.count,
              avg_duration: ops.sum(&:duration) / ops.count
            }
          end
        }
      end

      def calculate_execution_frequency
        return 0 if operations.empty? || operations.count < 2

        time_span = operations.last.occurred_at - operations.first.occurred_at
        return operations.count if time_span <= 0

        (operations.count / time_span.in_hours).round(2)
      end

      def calculate_location_distribution(backtraces)
        return {} if backtraces.empty?

        total = backtraces.length
        distribution = backtraces.tally.transform_values { |count| (count.to_f / total * 100).round(1) }

        # Sort by frequency and return top locations
        distribution.sort_by { |_, percentage| -percentage }.first(10).to_h
      end

      def identify_code_hotspots(backtraces)
        return [] if backtraces.empty?

        # Group by file/method to identify hotspots
        hotspots = []

        # Group by controller actions
        controller_hotspots = group_by_controller_actions(backtraces)
        hotspots.concat(controller_hotspots)

        # Group by model methods
        model_hotspots = group_by_model_methods(backtraces)
        hotspots.concat(model_hotspots)

        # Group by file
        file_hotspots = group_by_files(backtraces)
        hotspots.concat(file_hotspots)

        # Sort by frequency and return top hotspots
        hotspots.sort_by { |hotspot| -hotspot[:count] }.first(10)
      end

      def group_by_controller_actions(backtraces)
        controller_traces = backtraces.select { |trace| trace.include?("app/controllers/") }

        controller_actions = controller_traces.filter_map do |trace|
          match = trace.match(%r{app/controllers/(.+?)\.rb.*in `(.+?)'})
          next unless match

          controller = match[1].gsub("_controller", "").humanize
          action = match[2]
          "#{controller}##{action}"
        end

        build_hotspot_data(controller_actions, "controller_action")
      end

      def group_by_model_methods(backtraces)
        model_traces = backtraces.select { |trace| trace.include?("app/models/") }

        model_methods = model_traces.filter_map do |trace|
          match = trace.match(%r{app/models/(.+?)\.rb.*in `(.+?)'})
          next unless match

          model = match[1].classify
          method = match[2]
          "#{model}.#{method}"
        end

        build_hotspot_data(model_methods, "model_method")
      end

      def group_by_files(backtraces)
        files = backtraces.filter_map do |trace|
          match = trace.match(%r{(app/[^:]+)})
          match[1] if match
        end

        build_hotspot_data(files, "file")
      end

      def build_hotspot_data(items, type)
        return [] if items.empty?

        item_counts = items.tally
        total_operations = operations.count

        item_counts.map do |item, count|
          {
            type: type,
            location: item,
            count: count,
            percentage: (count.to_f / total_operations * 100).round(1),
            operations_per_execution: (count.to_f / item_counts.values.sum * total_operations).round(2)
          }
        end
      end

      def analyze_execution_contexts(backtraces)
        return {} if backtraces.empty?

        contexts = {
          framework_layers: analyze_framework_layers(backtraces),
          application_layers: analyze_application_layers(backtraces),
          gem_usage: analyze_gem_usage(backtraces),
          database_access_patterns: analyze_database_access_patterns(backtraces)
        }

        contexts
      end

      def analyze_framework_layers(backtraces)
        layers = {
          controller: backtraces.count { |trace| trace.include?("app/controllers/") },
          model: backtraces.count { |trace| trace.include?("app/models/") },
          view: backtraces.count { |trace| trace.include?("app/views/") },
          service: backtraces.count { |trace| trace.include?("app/services/") },
          job: backtraces.count { |trace| trace.include?("app/jobs/") },
          rails_framework: backtraces.count { |trace| trace.include?("railties") || trace.include?("actionpack") },
          activerecord: backtraces.count { |trace| trace.include?("activerecord") }
        }

        total = backtraces.count
        layers.transform_values { |count| { count: count, percentage: (count.to_f / total * 100).round(1) } }
      end

      def analyze_application_layers(backtraces)
        app_traces = backtraces.select { |trace| trace.include?("app/") }

        layers = {}
        app_traces.each do |trace|
          layer = extract_app_layer(trace)
          layers[layer] ||= 0
          layers[layer] += 1
        end

        total = app_traces.count
        layers.transform_values { |count| { count: count, percentage: (count.to_f / total * 100).round(1) } }
      end

      def extract_app_layer(trace)
        case trace
        when /app\/controllers/ then :controllers
        when /app\/models/ then :models
        when /app\/services/ then :services
        when /app\/jobs/ then :jobs
        when /app\/mailers/ then :mailers
        when /app\/helpers/ then :helpers
        when /app\/views/ then :views
        when /app\/lib/ then :lib
        else :other
        end
      end

      def analyze_gem_usage(backtraces)
        gem_traces = backtraces.reject { |trace| trace.include?("app/") || trace.include?("config/") }

        gems = gem_traces.filter_map do |trace|
          # Extract gem name from path like "/gems/gem_name-version/lib/..."
          match = trace.match(%r{/gems/([^/]+)/})
          match[1].split("-").first if match
        end

        gem_counts = gems.tally
        total = gem_traces.count

        gem_counts.transform_values { |count| { count: count, percentage: (count.to_f / total * 100).round(1) } }
                 .sort_by { |_, data| -data[:count] }
                 .first(5)
                 .to_h
      end

      def analyze_database_access_patterns(backtraces)
        db_traces = backtraces.select { |trace|
          trace.include?("activerecord") ||
          trace.include?("execute_query") ||
          trace.include?("adapter")
        }

        {
          total_db_operations: db_traces.count,
          percentage_db_operations: (db_traces.count.to_f / backtraces.count * 100).round(1),
          common_db_methods: extract_common_db_methods(db_traces)
        }
      end

      def extract_common_db_methods(db_traces)
        methods = db_traces.filter_map do |trace|
          match = trace.match(/in `(.+?)'/)
          match[1] if match
        end

        methods.tally.sort_by { |_, count| -count }.first(5).to_h
      end
    end
  end
end
