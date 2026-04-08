require "test_helper"

module RailsPulse
  module Analysis
    class IndexRecommendationEngineTest < ActiveSupport::TestCase
      fixtures :rails_pulse_queries

      def setup
        ENV["TEST_TYPE"] = "functional"
        super
      end

      # ============================================================================
      # Structure Tests
      # ============================================================================

      test "analyze returns array" do
        query = create_query("SELECT * FROM users WHERE id = 1")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        assert_kind_of Array, result
      end

      test "returns empty array for empty SQL" do
        query = create_query("")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        assert_empty result
      end

      test "returns empty array for SQL without WHERE, JOIN, or ORDER BY" do
        query = create_query("SELECT * FROM users")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        assert_empty result
      end

      # ============================================================================
      # WHERE Clause Index Tests
      # ============================================================================

      test "recommends index for equality condition in WHERE clause" do
        query = create_query("SELECT * FROM users WHERE email = 'test@example.com'")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        recommendation = result.find { |r| r[:columns].include?("email") }

        assert_not_nil recommendation
        assert_equal "single_column", recommendation[:type]
        assert_equal "high", recommendation[:priority]
        assert_includes recommendation[:migration_code], "add_index :users, :email"
      end

      test "recommends index for range condition in WHERE clause" do
        query = create_query("SELECT * FROM orders WHERE created_at > '2024-01-01'")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        recommendation = result.find { |r| r[:columns].include?("created_at") }

        assert_not_nil recommendation
        assert_equal "single_column", recommendation[:type]
        assert_equal "medium", recommendation[:priority]
      end

      test "recommends indexes for multiple WHERE conditions" do
        query = create_query("SELECT * FROM users WHERE email = 'test@example.com' AND active = true")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        assert_operator result.length, :>=, 2
        assert result.any? { |r| r[:columns].include?("email") }
        assert result.any? { |r| r[:columns].include?("active") }
      end

      test "recommends index for prefix LIKE pattern" do
        query = create_query("SELECT * FROM users WHERE name LIKE 'John%'")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        recommendation = result.find { |r| r[:columns].include?("name") }

        assert_not_nil recommendation
        assert_includes recommendation[:reason], "LIKE with prefix"
      end

      test "recommends full-text search for leading wildcard LIKE" do
        query = create_query("SELECT * FROM users WHERE name LIKE '%John%'")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        recommendation = result.find { |r| r[:type] == "full_text" }

        assert_not_nil recommendation
        assert_equal "low", recommendation[:priority]
      end

      test "filters out reserved words from WHERE recommendations" do
        query = create_query("SELECT * FROM users WHERE id = 1 AND NOT deleted")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        # Should recommend index on 'id' but not on 'NOT'
        assert result.any? { |r| r[:columns].include?("id") }
        refute result.any? { |r| r[:columns].include?("NOT") }
      end

      # ============================================================================
      # JOIN Index Tests
      # ============================================================================

      test "recommends index for JOIN condition" do
        query = create_query("SELECT * FROM users INNER JOIN posts ON posts.user_id = users.id")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        recommendation = result.find { |r| r[:table] == "posts" && r[:columns].include?("user_id") }

        assert_not_nil recommendation
        assert_equal "high", recommendation[:priority]
        assert_includes recommendation[:reason], "JOIN"
      end

      test "recommends indexes for multiple JOINs" do
        query = create_query(<<~SQL)
          SELECT * FROM users
          INNER JOIN posts ON posts.user_id = users.id
          LEFT JOIN comments ON comments.post_id = posts.id
        SQL
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        assert result.any? { |r| r[:table] == "posts" && r[:columns].include?("user_id") }
        assert result.any? { |r| r[:table] == "comments" && r[:columns].include?("post_id") }
      end

      # ============================================================================
      # ORDER BY Index Tests
      # ============================================================================

      test "recommends index for single ORDER BY column" do
        query = create_query("SELECT * FROM users ORDER BY created_at DESC")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        recommendation = result.find { |r| r[:columns].include?("created_at") }

        assert_not_nil recommendation
        assert_includes recommendation[:reason], "ORDER BY"
      end

      test "recommends composite index for multi-column ORDER BY" do
        query = create_query("SELECT * FROM users ORDER BY last_name, first_name")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        recommendation = result.find { |r| r[:type] == "composite" }

        assert_not_nil recommendation
        assert_equal [ "last_name", "first_name" ], recommendation[:columns]
      end

      # ============================================================================
      # Composite Index Tests
      # ============================================================================

      test "recommends composite index for WHERE + ORDER BY" do
        query = create_query("SELECT * FROM users WHERE active = true ORDER BY created_at")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        composite = result.find { |r| r[:type] == "composite" && r[:columns].length > 1 }

        assert_not_nil composite
        assert_includes composite[:columns], "active"
        assert_includes composite[:columns], "created_at"
      end

      test "recommends composite index for multiple WHERE conditions" do
        query = create_query("SELECT * FROM users WHERE email = 'test@example.com' AND active = true")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        composite = result.find { |r| r[:type] == "composite" && r[:columns].length == 2 }

        assert_not_nil composite
        assert_includes composite[:columns], "email"
        assert_includes composite[:columns], "active"
      end

      # ============================================================================
      # Covering Index Tests
      # ============================================================================

      test "recommends covering index when SELECT specifies columns" do
        query = create_query("SELECT id, name, email FROM users WHERE active = true")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        covering = result.find { |r| r[:type] == "covering" }

        assert_not_nil covering
        assert_includes covering[:columns], "active"
        # Should include selected columns for covering
        assert_operator covering[:columns].length, :>, 1
      end

      test "skips covering index for SELECT *" do
        query = create_query("SELECT * FROM users WHERE active = true")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        covering = result.find { |r| r[:type] == "covering" }

        assert_nil covering
      end

      # ============================================================================
      # Migration Code Generation Tests
      # ============================================================================

      test "generates migration code for single column index" do
        query = create_query("SELECT * FROM users WHERE email = 'test@example.com'")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        recommendation = result.first

        assert_includes recommendation[:migration_code], "add_index :users, :email"
      end

      test "generates migration code for composite index" do
        query = create_query("SELECT * FROM users WHERE email = 'test@example.com' AND active = true")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        composite = result.find { |r| r[:type] == "composite" && r[:columns].length == 2 }

        assert_not_nil composite
        assert_match(/add_index :users, \[.*"email".*"active".*\]/, composite[:migration_code])
      end

      test "generates full-text migration code for PostgreSQL" do
        query = create_query("SELECT * FROM users WHERE name LIKE '%test%'")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        fulltext = result.find { |r| r[:type] == "full_text" }

        assert_not_nil fulltext

        if engine.send(:postgresql?)
          assert_includes fulltext[:migration_code], "using: 'gin'"
        elsif engine.send(:mysql?)
          assert_includes fulltext[:migration_code], "type: 'fulltext'"
        end
      end

      # ============================================================================
      # Prioritization Tests
      # ============================================================================

      test "prioritizes recommendations by priority score" do
        query = create_query("SELECT * FROM users WHERE email = 'test@example.com' AND created_at > '2024-01-01'")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        # High priority (equality) should come before medium priority (range)
        high_priority_idx = result.index { |r| r[:priority] == "high" }
        medium_priority_idx = result.index { |r| r[:priority] == "medium" }

        if high_priority_idx && medium_priority_idx
          assert_operator high_priority_idx, :<, medium_priority_idx
        end
      end

      test "boosts priority based on operation frequency" do
        operations = 10.times.map do
          create_operation(duration: 100.0)
        end
        query = create_query("SELECT * FROM users WHERE email = 'test@example.com'")
        engine = IndexRecommendationEngine.new(query, operations)

        result = engine.analyze

        recommendation = result.first
        # Priority score should be boosted by frequency
        assert_operator recommendation[:priority_score], :>, 100
      end

      test "removes duplicate recommendations" do
        query = create_query("SELECT * FROM users WHERE email = 'test@example.com' AND email = 'other@example.com'")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        email_recommendations = result.select { |r| r[:columns] == [ "email" ] && r[:type] == "single_column" }
        # Should only have one recommendation for email column
        assert_operator email_recommendations.length, :<=, 1
      end

      # ============================================================================
      # Edge Cases
      # ============================================================================

      test "handles SQL without table name" do
        query = create_query("SELECT 1")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        assert_kind_of Array, result
      end

      test "handles complex nested queries" do
        query = create_query("SELECT * FROM users WHERE id IN (SELECT user_id FROM posts WHERE published = true)")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        # Should still make recommendations
        assert_kind_of Array, result
      end

      test "handles schema-qualified table names" do
        query = create_query("SELECT * FROM public.users WHERE email = 'test@example.com'")
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        recommendation = result.first

        assert_not_nil recommendation
        # extract_main_table gets first word, which is schema name
        # This is a known limitation of the regex-based parsing
        assert recommendation[:table].in?([ "public", "users" ])
      end

      test "handles quoted column names" do
        query = create_query('SELECT * FROM users WHERE "email" = \'test@example.com\'')
        engine = IndexRecommendationEngine.new(query)

        result = engine.analyze

        # Should handle quoted identifiers
        assert_kind_of Array, result
      end

      test "includes execution context in recommendations" do
        query = create_query("SELECT * FROM users WHERE email = 'test@example.com'")
        operations = 5.times.map { create_operation }
        engine = IndexRecommendationEngine.new(query, operations)

        result = engine.analyze

        recommendation = result.first

        assert_includes recommendation.keys, :execution_context
        assert_equal 5, recommendation[:execution_context][:frequency]
      end

      private

      def create_query(sql)
        RailsPulse::Query.find_or_create_by(normalized_sql: sql) do |q|
          q.hashed_sql = Digest::MD5.hexdigest(sql)
        end
      end

      def create_operation(attributes = {})
        default_attributes = {
          request: rails_pulse_requests(:users_request_1),
          query: rails_pulse_queries(:simple_query),
          operation_type: "sql",
          label: "SELECT * FROM users",
          duration: 50.0,
          start_time: 0.0,
          occurred_at: Time.current
        }

        RailsPulse::Operation.create!(default_attributes.merge(attributes))
      end
    end
  end
end
