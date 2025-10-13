require "test_helper"

module RailsPulse
  class SqlQueryNormalizerTest < ActiveSupport::TestCase
    test "normalize preserves table and column names while normalizing values" do
      examples = {
        # Basic SELECT with WHERE clause
        "SELECT users.* FROM users WHERE users.id = 123" =>
          "SELECT users.* FROM users WHERE users.id = ?",

        # Multiple conditions
        "SELECT posts.* FROM posts WHERE posts.user_id = 456 AND posts.status = 'published'" =>
          "SELECT posts.* FROM posts WHERE posts.user_id = ? AND posts.status = ?",

        # JOIN queries
        "SELECT users.name, posts.title FROM users JOIN posts ON users.id = posts.user_id WHERE users.id = 789" =>
          "SELECT users.name, posts.title FROM users JOIN posts ON users.id = posts.user_id WHERE users.id = ?",

        # LIMIT and OFFSET
        "SELECT * FROM products LIMIT 10 OFFSET 20" =>
          "SELECT * FROM products LIMIT ? OFFSET ?",

        # Floating point numbers
        "SELECT * FROM items WHERE price > 19.99" =>
          "SELECT * FROM items WHERE price > ?",

        # Boolean values
        "SELECT * FROM users WHERE active = true AND verified = false" =>
          "SELECT * FROM users WHERE active = ? AND verified = ?",

        # NULL values (preserved)
        "SELECT * FROM users WHERE deleted_at IS NULL" =>
          "SELECT * FROM users WHERE deleted_at IS NULL",

        # String literals with quotes
        'SELECT * FROM users WHERE name = "John Doe" AND email = \'john@example.com\'' =>
          "SELECT * FROM users WHERE name = ? AND email = ?",

        # Preserve quoted identifiers
        'SELECT "user_id", `created_at` FROM "user_sessions"' =>
          'SELECT "user_id", `created_at` FROM "user_sessions"',

        # Complex string with escapes
        "SELECT * FROM logs WHERE message = 'User said: \"Hello World\"'" =>
          "SELECT * FROM logs WHERE message = ?"
      }

      examples.each do |input, expected|
        result = RailsPulse::SqlQueryNormalizer.normalize(input)

        assert_equal expected, result, "Failed for input: #{input}"
      end
    end

    test "normalize handles IN clauses correctly" do
      examples = {
        # Simple IN clause
        "SELECT * FROM users WHERE id IN (1, 2, 3)" =>
          "SELECT * FROM users WHERE id IN (?, ?, ?)",

        # IN clause with strings
        "SELECT * FROM users WHERE status IN ('active', 'pending', 'inactive')" =>
          "SELECT * FROM users WHERE status IN (?, ?, ?)",

        # Single value IN clause
        "SELECT * FROM users WHERE id IN (123)" =>
          "SELECT * FROM users WHERE id IN (?)",

        # IN clause with mixed types
        "SELECT * FROM events WHERE type IN ('login', 'logout') AND user_id IN (1, 2)" =>
          "SELECT * FROM events WHERE type IN (?, ?) AND user_id IN (?, ?)"
      }

      examples.each do |input, expected|
        result = RailsPulse::SqlQueryNormalizer.normalize(input)

        assert_equal expected, result, "Failed for input: #{input}"
      end
    end

    test "normalize handles BETWEEN clauses" do
      examples = {
        "SELECT * FROM orders WHERE created_at BETWEEN '2023-01-01' AND '2023-12-31'" =>
          "SELECT * FROM orders WHERE created_at BETWEEN ? AND ?",

        "SELECT * FROM products WHERE price BETWEEN 10.00 AND 100.00" =>
          "SELECT * FROM products WHERE price BETWEEN ? AND ?"
      }

      examples.each do |input, expected|
        result = RailsPulse::SqlQueryNormalizer.normalize(input)

        assert_equal expected, result, "Failed for input: #{input}"
      end
    end

    test "normalize preserves identifiers with numbers" do
      examples = {
        # Table names with numbers
        "SELECT * FROM users2 WHERE id = 123" =>
          "SELECT * FROM users2 WHERE id = ?",

        # Column names with numbers
        "SELECT user_id2, created_at FROM posts WHERE user_id2 = 456" =>
          "SELECT user_id2, created_at FROM posts WHERE user_id2 = ?",

        # Schema prefixed tables
        "SELECT * FROM app_v2.users WHERE id = 789" =>
          "SELECT * FROM app_v2.users WHERE id = ?"
      }

      examples.each do |input, expected|
        result = RailsPulse::SqlQueryNormalizer.normalize(input)

        assert_equal expected, result, "Failed for input: #{input}"
      end
    end

    test "normalize handles edge cases gracefully" do
      examples = {
        # Empty/nil input
        "" => "",
        nil => nil,

        # Already normalized query
        "SELECT * FROM users WHERE id = ?" =>
          "SELECT * FROM users WHERE id = ?",

        # Multiple whitespace normalization
        "SELECT   *    FROM   users   WHERE  id = 123" =>
          "SELECT * FROM users WHERE id = ?"
      }

      examples.each do |input, expected|
        result = RailsPulse::SqlQueryNormalizer.normalize(input)
        if expected.nil?
          assert_nil result, "Failed for input: #{input.inspect}"
        else
          assert_equal expected, result, "Failed for input: #{input.inspect}"
        end
      end
    end

    test "normalize creates distinct queries for different table/column combinations" do
      # These should create different normalized queries
      queries = [
        "SELECT users.* FROM users WHERE users.id = 123",
        "SELECT posts.* FROM posts WHERE posts.id = 123",
        "SELECT users.* FROM users WHERE users.email = 'test@example.com'",
        "SELECT users.name FROM users WHERE users.id = 123"
      ]

      normalized_queries = queries.map { |q| RailsPulse::SqlQueryNormalizer.normalize(q) }

      # All should be different since they involve different tables/columns
      assert_equal queries.length, normalized_queries.uniq.length,
        "Expected all normalized queries to be unique: #{normalized_queries}"
    end

    test "normalize handles complex SQL features" do
      examples = {
        # Multiple functions
        "SELECT COUNT(*), AVG(price) FROM products WHERE created_at > '2023-01-01'" =>
          "SELECT COUNT(*), AVG(price) FROM products WHERE created_at > ?",

        # CASE statements
        "SELECT CASE WHEN age > 18 THEN 'adult' ELSE 'minor' END FROM users" =>
          "SELECT CASE WHEN age > ? THEN ? ELSE ? END FROM users",

        # Window functions
        "SELECT *, ROW_NUMBER() OVER (ORDER BY created_at) FROM posts WHERE user_id = 123" =>
          "SELECT *, ROW_NUMBER() OVER (ORDER BY created_at) FROM posts WHERE user_id = ?",

        # Simple subquery (current implementation treats whole IN content as values)
        "SELECT * FROM users WHERE id IN (SELECT user_id FROM posts)" =>
          "SELECT * FROM users WHERE id IN (?)"
      }

      examples.each do |input, expected|
        result = RailsPulse::SqlQueryNormalizer.normalize(input)

        assert_equal expected, result, "Failed for input: #{input}"
      end
    end

    test "normalize handles various SQL dialects" do
      examples = {
        # PostgreSQL style
        'SELECT "users"."name" FROM "users" WHERE "users"."id" = 123' =>
          'SELECT "users"."name" FROM "users" WHERE "users"."id" = ?',

        # MySQL style
        "SELECT `users`.`name` FROM `users` WHERE `users`.`id` = 123" =>
          "SELECT `users`.`name` FROM `users` WHERE `users`.`id` = ?",

        # Mixed quoting
        'SELECT `user_id`, "created_at" FROM user_sessions WHERE active = true' =>
          'SELECT `user_id`, "created_at" FROM user_sessions WHERE active = ?'
      }

      examples.each do |input, expected|
        result = RailsPulse::SqlQueryNormalizer.normalize(input)

        assert_equal expected, result, "Failed for input: #{input}"
      end
    end

    test "class method normalize delegates to instance" do
      query = "SELECT * FROM users WHERE id = 123"
      expected = "SELECT * FROM users WHERE id = ?"

      # Test class method
      result = RailsPulse::SqlQueryNormalizer.normalize(query)

      assert_equal expected, result

      # Test instance method
      normalizer = RailsPulse::SqlQueryNormalizer.new(query)
      result = normalizer.normalize

      assert_equal expected, result
    end

    test "service is stateless and reusable" do
      query = "SELECT * FROM users WHERE id = 123"
      expected = "SELECT * FROM users WHERE id = ?"

      # Multiple calls should return same result
      3.times do
        result = RailsPulse::SqlQueryNormalizer.normalize(query)

        assert_equal expected, result
      end

      # Different instances should return same result
      normalizer1 = RailsPulse::SqlQueryNormalizer.new(query)
      normalizer2 = RailsPulse::SqlQueryNormalizer.new(query)

      assert_equal normalizer1.normalize, normalizer2.normalize
    end
  end
end
