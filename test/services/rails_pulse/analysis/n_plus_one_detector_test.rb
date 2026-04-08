require "test_helper"

module RailsPulse
  module Analysis
    class NPlusOneDetectorTest < ActiveSupport::TestCase
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
        operations = create_operations(count: 3)
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        assert_kind_of Hash, result
        assert_includes result.keys, :is_likely_n_plus_one
        assert_includes result.keys, :confidence_score
        assert_includes result.keys, :evidence
        assert_includes result.keys, :suggested_fixes
        assert_includes result.keys, :execution_patterns
      end

      # ============================================================================
      # Empty Operations Tests
      # ============================================================================

      test "returns default result for empty operations" do
        detector = NPlusOneDetector.new(@query, [])

        result = detector.analyze

        refute result[:is_likely_n_plus_one]
        assert_equal 0, result[:confidence_score]
        assert_empty result[:evidence]
        assert_empty result[:suggested_fixes]
        assert_equal Hash.new, result[:execution_patterns]
      end

      # ============================================================================
      # N+1 Detection Tests
      # ============================================================================

      test "detects N+1 pattern with repetitive queries in single request" do
        # Create 5 identical queries within short time window (0.1 seconds)
        operations = create_operations(
          count: 5,
          label: "SELECT * FROM posts WHERE user_id = ?",
          time_spacing: 0.01.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        assert result[:is_likely_n_plus_one]
        assert_operator result[:confidence_score], :>, 0
        assert_operator result[:evidence].length, :>, 0
      end

      test "does not detect N+1 pattern with queries below threshold" do
        # Only 2 identical queries (below REPETITION_THRESHOLD of 3)
        operations = create_operations(
          count: 2,
          label: "SELECT * FROM posts WHERE user_id = ?",
          time_spacing: 0.01.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        refute result[:is_likely_n_plus_one]
      end

      test "does not detect N+1 pattern when queries are spread across different requests" do
        # 5 queries but widely spaced (beyond REQUEST_GROUPING_WINDOW)
        operations = create_operations(
          count: 5,
          label: "SELECT * FROM posts WHERE user_id = ?",
          time_spacing: 1.second
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        # Should not detect because they're in different request groups
        refute result[:is_likely_n_plus_one]
      end

      # ============================================================================
      # Confidence Score Tests
      # ============================================================================

      test "calculates confidence score based on repetition count" do
        # 5 repetitions = confidence boost of 5 * 10 = 50
        operations = create_operations(
          count: 5,
          label: "SELECT * FROM posts WHERE user_id = ?",
          time_spacing: 0.01.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        assert_operator result[:confidence_score], :>=, 30
      end

      test "caps confidence score at 100" do
        # Many repetitions to exceed 100
        operations = create_operations(
          count: 20,
          label: "SELECT * FROM posts WHERE user_id = ?",
          time_spacing: 0.001.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        assert_operator result[:confidence_score], :<=, 100
      end

      # ============================================================================
      # Evidence Tests
      # ============================================================================

      test "provides evidence for repetitive queries" do
        operations = create_operations(
          count: 5,
          label: "SELECT * FROM posts WHERE user_id = ?",
          time_spacing: 0.01.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        repetitive_evidence = result[:evidence].find { |e| e[:type] == "repetitive_query" }

        assert_not_nil repetitive_evidence
        assert_equal 5, repetitive_evidence[:occurrences]
        assert_includes repetitive_evidence[:description], "5 times"
      end

      test "detects single record lookup pattern" do
        operations = create_operations(
          count: 5,
          label: "SELECT * FROM posts WHERE id = ?",
          time_spacing: 0.01.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        lookup_evidence = result[:evidence].find { |e| e[:type] == "single_record_lookup" }

        assert_not_nil lookup_evidence
        assert_includes lookup_evidence[:description], "eager loading"
      end

      # ============================================================================
      # Request Grouping Tests
      # ============================================================================

      test "groups operations by time windows" do
        # Create two groups of operations separated by more than REQUEST_GROUPING_WINDOW
        group1 = create_operations(
          count: 3,
          base_time: Time.current,
          time_spacing: 0.01.seconds
        )
        group2 = create_operations(
          count: 3,
          base_time: Time.current + 5.seconds,
          time_spacing: 0.01.seconds
        )
        all_operations = group1 + group2

        detector = NPlusOneDetector.new(@query, all_operations)

        result = detector.analyze

        # Should detect N+1 in both groups if queries are identical
        assert result[:is_likely_n_plus_one]
      end

      test "ignores single operations in grouping" do
        # Create one operation, then a gap, then multiple operations
        single_op = create_operations(count: 1, base_time: Time.current)
        group_ops = create_operations(
          count: 4,
          base_time: Time.current + 5.seconds,
          time_spacing: 0.01.seconds
        )
        all_operations = single_op + group_ops

        detector = NPlusOneDetector.new(@query, all_operations)

        result = detector.analyze

        # Should only analyze the group, not the single operation
        assert result[:is_likely_n_plus_one]
      end

      # ============================================================================
      # Execution Pattern Tests
      # ============================================================================

      test "calculates execution patterns with multiple operations" do
        operations = create_operations(
          count: 10,
          base_time: Time.current,
          time_spacing: 1.second
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        patterns = result[:execution_patterns]

        assert_equal 10, patterns[:total_executions]
        assert_operator patterns[:time_span_minutes], :>, 0
        assert_operator patterns[:executions_per_minute], :>, 0
      end

      test "calculates time span in minutes" do
        operations = create_operations(
          count: 5,
          base_time: Time.current,
          time_spacing: 30.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        patterns = result[:execution_patterns]
        # 4 gaps * 30 seconds = 120 seconds = 2 minutes
        assert_in_delta 2.0, patterns[:time_span_minutes], 0.1
      end

      test "calculates executions per minute" do
        # 10 operations over 2 minutes = 5 per minute
        operations = create_operations(
          count: 10,
          base_time: Time.current,
          time_spacing: (2.minutes / 9)
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        patterns = result[:execution_patterns]

        assert_in_delta 5.0, patterns[:executions_per_minute], 0.5
      end

      test "finds peak execution periods" do
        # Create operations with one peak period
        normal_ops = create_operations(count: 2, base_time: Time.current)
        peak_ops = create_operations(count: 10, base_time: Time.current + 6.minutes, time_spacing: 5.seconds)
        all_operations = normal_ops + peak_ops

        detector = NPlusOneDetector.new(@query, all_operations)

        result = detector.analyze

        patterns = result[:execution_patterns]

        assert_operator patterns[:peak_execution_periods].length, :>, 0
      end

      test "returns empty peak periods when operations are evenly distributed" do
        operations = create_operations(
          count: 10,
          base_time: Time.current,
          time_spacing: 1.minute
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        patterns = result[:execution_patterns]
        # All windows should be similar, so no peaks
        assert_operator patterns[:peak_execution_periods].length, :<=, 1
      end

      # ============================================================================
      # Execution Context Tests
      # ============================================================================

      test "extracts controller actions from codebase locations" do
        operations = [
          create_operation(codebase_location: "app/controllers/users_controller#index"),
          create_operation(codebase_location: "app/controllers/users_controller#index"),
          create_operation(codebase_location: "app/controllers/posts_controller#show")
        ]
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        contexts = result[:execution_patterns][:common_execution_contexts]

        assert_equal 2, contexts[:controller_actions]["users_controller#index"]
        assert_equal 1, contexts[:controller_actions]["posts_controller#show"]
      end

      test "extracts model methods from codebase locations" do
        operations = [
          create_operation(codebase_location: "app/models/user.rb:25 in `recent_posts'"),
          create_operation(codebase_location: "app/models/user.rb:25 in `recent_posts'"),
          create_operation(codebase_location: "app/models/post.rb:10 in `author'")
        ]
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        contexts = result[:execution_patterns][:common_execution_contexts]

        assert_equal 2, contexts[:model_methods]["user.recent_posts"]
        assert_equal 1, contexts[:model_methods]["post.author"]
      end

      test "counts unique and total execution contexts" do
        operations = [
          create_operation(codebase_location: "app/controllers/users_controller#index"),
          create_operation(codebase_location: "app/controllers/users_controller#index"),
          create_operation(codebase_location: "app/controllers/posts_controller#show")
        ]
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        contexts = result[:execution_patterns][:common_execution_contexts]

        assert_equal 2, contexts[:unique_locations]
        assert_equal 3, contexts[:total_contexts]
      end

      test "handles operations without codebase_location" do
        operations = [
          create_operation(codebase_location: nil),
          create_operation(codebase_location: "")
        ]
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        contexts = result[:execution_patterns][:common_execution_contexts]
        # Code still creates structure but with empty/minimal data
        assert_empty contexts[:controller_actions]
        assert_empty contexts[:model_methods]
      end

      # ============================================================================
      # Suggested Fixes Tests
      # ============================================================================

      test "suggests eager loading fixes when N+1 detected" do
        operations = create_operations(
          count: 5,
          label: "SELECT * FROM posts WHERE user_id = ?",
          time_spacing: 0.01.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        assert_operator result[:suggested_fixes].length, :>, 0
        includes_fix = result[:suggested_fixes].find { |f| f[:type] == "includes" }

        assert_not_nil includes_fix
        assert_includes includes_fix[:description], "includes()"
      end

      test "provides ActiveRecord fix examples" do
        operations = create_operations(
          count: 5,
          label: "SELECT * FROM posts WHERE user_id = ?",
          time_spacing: 0.01.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        fix_types = result[:suggested_fixes].map { |f| f[:type] }

        assert_includes fix_types, "includes"
        assert_includes fix_types, "preload"
        assert_includes fix_types, "joins"
      end

      test "suggests specific association from foreign key column" do
        operations = create_operations(
          count: 5,
          label: "SELECT * FROM posts WHERE user_id = ?",
          time_spacing: 0.01.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        eager_fix = result[:suggested_fixes].find { |f| f[:type] == "eager_loading" }

        assert_not_nil eager_fix
        assert_includes eager_fix[:code_example], "Post.includes(:user)"
      end

      test "provides generic suggestion when association cannot be determined" do
        operations = create_operations(
          count: 5,
          label: "SELECT * FROM posts WHERE name = ?",
          time_spacing: 0.01.seconds
        )
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        eager_fix = result[:suggested_fixes].find { |f| f[:type] == "eager_loading" }

        assert_not_nil eager_fix
        assert_includes eager_fix[:code_example], "Model.includes(:association)"
      end

      # ============================================================================
      # Edge Cases
      # ============================================================================

      test "handles single operation gracefully" do
        operation = create_operation
        detector = NPlusOneDetector.new(@query, [ operation ])

        result = detector.analyze

        refute result[:is_likely_n_plus_one]
        assert_equal 0, result[:confidence_score]
      end

      test "handles operations with same timestamp" do
        base_time = Time.current
        operations = 5.times.map do
          create_operation(occurred_at: base_time)
        end
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        # Should still group and detect
        assert result[:is_likely_n_plus_one]
      end

      test "normalizes different query values to same pattern" do
        operations = [
          create_operation(label: "SELECT * FROM posts WHERE id = 1"),
          create_operation(label: "SELECT * FROM posts WHERE id = 2"),
          create_operation(label: "SELECT * FROM posts WHERE id = 3"),
          create_operation(label: "SELECT * FROM posts WHERE id = 4"),
          create_operation(label: "SELECT * FROM posts WHERE id = 5")
        ]
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        # All should be normalized to same pattern and detected as N+1
        assert result[:is_likely_n_plus_one]
      end

      test "distinguishes different query patterns" do
        operations = [
          create_operation(label: "SELECT * FROM posts WHERE id = ?"),
          create_operation(label: "SELECT * FROM posts WHERE user_id = ?"),
          create_operation(label: "SELECT * FROM users WHERE id = ?")
        ]
        detector = NPlusOneDetector.new(@query, operations)

        result = detector.analyze

        # Different patterns, none repeated enough to trigger
        refute result[:is_likely_n_plus_one]
      end

      private

      def create_operations(count:, label: nil, base_time: nil, time_spacing: 0.01.seconds)
        base_time ||= Time.current
        label ||= "SELECT * FROM users WHERE id = ?"

        count.times.map do |i|
          create_operation(
            label: label,
            occurred_at: base_time + (i * time_spacing)
          )
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
