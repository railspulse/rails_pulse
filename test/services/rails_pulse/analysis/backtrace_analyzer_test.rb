require "test_helper"

module RailsPulse
  module Analysis
    class BacktraceAnalyzerTest < ActiveSupport::TestCase
      fixtures :rails_pulse_queries, :rails_pulse_requests

      def setup
        ENV["TEST_TYPE"] = "functional"
        super
        @query = rails_pulse_queries(:simple_query)
        travel_to Time.current
      end

      def teardown
        travel_back
        super
      end

      # ============================================================================
      # Structure Tests
      # ============================================================================

      test "analyze returns hash with required keys" do
        operations = create_operations_with_locations
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_kind_of Hash, result
        assert_includes result.keys, :total_executions
        assert_includes result.keys, :unique_locations
        assert_includes result.keys, :most_common_location
        assert_includes result.keys, :execution_frequency
        assert_includes result.keys, :location_distribution
        assert_includes result.keys, :code_hotspots
        assert_includes result.keys, :execution_contexts
        # Note: potential_n_plus_one removed - use NPlusOneDetector instead
      end

      # ============================================================================
      # Basic Statistics Tests
      # ============================================================================

      test "counts total executions" do
        operations = create_operations_with_locations(count: 5)
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_equal 5, result[:total_executions]
      end

      test "counts unique locations" do
        operations = [
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: "app/models/user.rb:25")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_equal 2, result[:unique_locations]
      end

      test "handles empty operations" do
        analyzer = BacktraceAnalyzer.new(@query, [])

        result = analyzer.analyze

        assert_equal 0, result[:total_executions]
        assert_equal 0, result[:unique_locations]
        assert_nil result[:most_common_location]
        assert_empty result[:location_distribution]
        assert_empty result[:code_hotspots]
      end

      test "handles operations without codebase_location" do
        operations = [
          create_operation(codebase_location: nil),
          create_operation(codebase_location: "")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_equal 2, result[:total_executions]
        # Empty string is kept by compact, so counts as 1 location
        assert_equal 1, result[:unique_locations]
      end

      # ============================================================================
      # Most Common Location Tests
      # ============================================================================

      test "identifies most common location" do
        operations = [
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: "app/models/user.rb:25")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_not_nil result[:most_common_location]
        assert_equal "app/controllers/users_controller.rb:10", result[:most_common_location][:location]
        assert_equal 3, result[:most_common_location][:count]
        assert_in_delta 75.0, result[:most_common_location][:percentage], 0.1
      end

      test "returns nil most_common_location when no locations" do
        operations = [create_operation(codebase_location: nil)]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_nil result[:most_common_location]
      end

      # ============================================================================
      # Execution Frequency Tests
      # ============================================================================

      test "calculates execution frequency per hour" do
        base_time = Time.current
        operations = [
          create_operation(occurred_at: base_time),
          create_operation(occurred_at: base_time + 1.hour)
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_in_delta 2.0, result[:execution_frequency], 0.1
      end

      test "returns zero frequency for single operation" do
        operations = [create_operation]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_equal 0, result[:execution_frequency]
      end

      test "handles operations with same timestamp" do
        base_time = Time.current
        operations = [
          create_operation(occurred_at: base_time),
          create_operation(occurred_at: base_time)
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        # Same time = return count
        assert_equal 2, result[:execution_frequency]
      end

      # ============================================================================
      # Location Distribution Tests
      # ============================================================================

      test "calculates location distribution percentages" do
        operations = [
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: "app/models/user.rb:25")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        distribution = result[:location_distribution]
        assert_in_delta 75.0, distribution["app/controllers/users_controller.rb:10"], 0.1
        assert_in_delta 25.0, distribution["app/models/user.rb:25"], 0.1
      end

      test "returns top 10 locations by frequency" do
        # Create 15 different locations
        operations = 15.times.map do |i|
          create_operation(codebase_location: "app/models/model_#{i}.rb:10")
        end
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_operator result[:location_distribution].length, :<=, 10
      end

      test "returns empty distribution for no locations" do
        operations = [create_operation(codebase_location: nil)]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_empty result[:location_distribution]
      end

      # ============================================================================
      # Code Hotspots Tests
      # ============================================================================

      test "identifies controller action hotspots" do
        operations = [
          create_operation(codebase_location: "app/controllers/users_controller.rb:10 in `index'"),
          create_operation(codebase_location: "app/controllers/users_controller.rb:10 in `index'"),
          create_operation(codebase_location: "app/controllers/posts_controller.rb:5 in `show'")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        hotspot = result[:code_hotspots].find { |h| h[:type] == "controller_action" && h[:location] == "Users#index" }
        assert_not_nil hotspot
        assert_equal 2, hotspot[:count]
      end

      test "identifies model method hotspots" do
        operations = [
          create_operation(codebase_location: "app/models/user.rb:25 in `recent_posts'"),
          create_operation(codebase_location: "app/models/user.rb:25 in `recent_posts'"),
          create_operation(codebase_location: "app/models/post.rb:10 in `author'")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        hotspot = result[:code_hotspots].find { |h| h[:type] == "model_method" && h[:location] == "User.recent_posts" }
        assert_not_nil hotspot
        assert_equal 2, hotspot[:count]
      end

      test "identifies file hotspots" do
        operations = [
          create_operation(codebase_location: "app/services/user_service.rb:10"),
          create_operation(codebase_location: "app/services/user_service.rb:20"),
          create_operation(codebase_location: "app/models/user.rb:5")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        file_hotspot = result[:code_hotspots].find { |h| h[:type] == "file" && h[:location] == "app/services/user_service.rb" }
        assert_not_nil file_hotspot
        assert_equal 2, file_hotspot[:count]
      end

      test "returns top 10 hotspots sorted by count" do
        # Create many operations
        operations = 15.times.map do |i|
          create_operation(codebase_location: "app/controllers/controller_#{i}.rb:10 in `index'")
        end
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_operator result[:code_hotspots].length, :<=, 10
      end

      test "returns empty hotspots for no locations" do
        operations = [create_operation(codebase_location: nil)]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_empty result[:code_hotspots]
      end

      # ============================================================================
      # Execution Contexts Tests
      # ============================================================================

      test "analyzes framework layers" do
        operations = [
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: "app/controllers/posts_controller.rb:5"),
          create_operation(codebase_location: "app/models/user.rb:25")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        layers = result[:execution_contexts][:framework_layers]
        assert_equal 2, layers[:controller][:count]
        assert_equal 1, layers[:model][:count]
      end

      test "analyzes application layers" do
        operations = [
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: "app/services/user_service.rb:5"),
          create_operation(codebase_location: "app/jobs/user_sync_job.rb:15")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        app_layers = result[:execution_contexts][:application_layers]
        assert_not_nil app_layers[:controllers]
        assert_not_nil app_layers[:services]
        assert_not_nil app_layers[:jobs]
      end

      test "analyzes gem usage" do
        operations = [
          create_operation(codebase_location: "/gems/devise-4.8.0/lib/devise/models/authenticatable.rb:10"),
          create_operation(codebase_location: "/gems/devise-4.8.0/lib/devise/strategies/authenticatable.rb:5"),
          create_operation(codebase_location: "/gems/pundit-2.1.0/lib/pundit.rb:20")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        gem_usage = result[:execution_contexts][:gem_usage]
        assert_equal 2, gem_usage["devise"][:count]
        assert_equal 1, gem_usage["pundit"][:count]
      end

      test "returns top 5 gems by usage" do
        operations = 10.times.map do |i|
          create_operation(codebase_location: "/gems/gem_#{i}-1.0.0/lib/gem_#{i}.rb:10")
        end
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        gem_usage = result[:execution_contexts][:gem_usage]
        assert_operator gem_usage.length, :<=, 5
      end

      # ============================================================================
      # N+1 Detection Note
      # ============================================================================
      # The simple N+1 detection that was in BacktraceAnalyzer has been removed
      # as it duplicated the more sophisticated NPlusOneDetector.
      # Use NPlusOneDetector directly for N+1 query detection.

      # ============================================================================
      # Edge Cases
      # ============================================================================

      test "handles mixed locations with and without backtraces" do
        operations = [
          create_operation(codebase_location: "app/controllers/users_controller.rb:10"),
          create_operation(codebase_location: nil),
          create_operation(codebase_location: "app/models/user.rb:25"),
          create_operation(codebase_location: "")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_equal 4, result[:total_executions]
        # Empty string is kept, so: users_controller, user, and "" = 3 unique
        assert_equal 3, result[:unique_locations]
      end

      test "handles malformed backtrace locations" do
        operations = [
          create_operation(codebase_location: "random string without structure"),
          create_operation(codebase_location: "app/controllers/users_controller.rb:10")
        ]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        # Should not crash, just process what it can
        assert_kind_of Hash, result
        assert_equal 2, result[:total_executions]
      end

      test "handles extremely long location paths" do
        long_path = "app/" + ("very_long_directory_name/" * 8) + "file.rb:10"
        operations = [create_operation(codebase_location: long_path)]
        analyzer = BacktraceAnalyzer.new(@query, operations)

        result = analyzer.analyze

        assert_kind_of Hash, result
        assert_equal 1, result[:total_executions]
      end

      private

      def create_operations_with_locations(count: 3)
        count.times.map do |i|
          create_operation(codebase_location: "app/models/user.rb:#{10 + i}")
        end
      end

      def create_operation(attributes = {})
        default_attributes = {
          request: rails_pulse_requests(:users_request_1),
          query: @query,
          operation_type: "sql",
          label: "SELECT * FROM users WHERE id = ?",
          duration: 50.0,
          start_time: 0.0,
          occurred_at: Time.current,
          codebase_location: "app/models/user.rb:10"
        }

        RailsPulse::Operation.create!(default_attributes.merge(attributes))
      end
    end
  end
end
