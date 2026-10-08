require "test_helper"
require "benchmark"

module RailsPulse
  class SqlQueryNormalizerTest < ActiveSupport::TestCase
    # Structure Tests

    test "class method normalize delegates to instance" do
      query = "SELECT * FROM users WHERE id = 123"
      expected = "SELECT * FROM users WHERE id = ?"

      assert_equal expected, RailsPulse::SqlQueryNormalizer.normalize(query)
      assert_equal expected, RailsPulse::SqlQueryNormalizer.new(query).normalize
    end

    test "service is stateless and reusable" do
      query = "SELECT * FROM users WHERE id = 123"
      expected = "SELECT * FROM users WHERE id = ?"

      3.times do
        assert_equal expected, RailsPulse::SqlQueryNormalizer.normalize(query)
      end

      normalizer1 = RailsPulse::SqlQueryNormalizer.new(query)
      normalizer2 = RailsPulse::SqlQueryNormalizer.new(query)

      assert_equal normalizer1.normalize, normalizer2.normalize
    end

    test "host_adapter reports the host application's primary adapter" do
      assert_equal ActiveRecord::Base.connection_db_config.adapter.to_s, RailsPulse::SqlQueryNormalizer.host_adapter
    end

    # Value Replacement

    test "normalize preserves table and column names while normalizing values" do
      assert_normalizes(
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
      )
    end

    test "normalize replaces numbers in every form ActiveRecord writes them" do
      assert_normalizes(
        # Ruby writes small and large floats in exponent form (0.00001.to_s)
        "SELECT * FROM t WHERE x = 1.0e-05 AND y = 1.0e+20" =>
          "SELECT * FROM t WHERE x = ? AND y = ?",
        "SELECT * FROM t WHERE x > 1e5 AND y < 2.5E-3" =>
          "SELECT * FROM t WHERE x > ? AND y < ?",

        # Negative numbers keep their sign outside the placeholder
        "SELECT * FROM t WHERE x = -5 AND y = -1.5" =>
          "SELECT * FROM t WHERE x = -? AND y = -?",

        # Casts keep their type
        "SELECT * FROM t WHERE created_at > '2024-01-01'::timestamp AND n = 5::int4" =>
          "SELECT * FROM t WHERE created_at > ?::timestamp AND n = ?::int4",

        # Intervals in both spellings
        "SELECT * FROM t WHERE a > NOW() - INTERVAL '7 days' AND b > NOW() - INTERVAL 7 DAY" =>
          "SELECT * FROM t WHERE a > NOW() - INTERVAL ? AND b > NOW() - INTERVAL ? DAY"
      )
    end

    test "normalize handles statements other than SELECT" do
      assert_normalizes(
        "INSERT INTO users (name, age) VALUES ('Jane', 30) RETURNING id" =>
          "INSERT INTO users (name, age) VALUES (?, ?) RETURNING id",

        "UPDATE users SET name = 'x', updated_at = '2024-01-01 00:00:00' WHERE id = 1" =>
          "UPDATE users SET name = ?, updated_at = ? WHERE id = ?",

        "DELETE FROM sessions WHERE expired_at < '2024-01-01' AND user_id = 7" =>
          "DELETE FROM sessions WHERE expired_at < ? AND user_id = ?"
      )
    end

    test "normalize handles complex SQL features" do
      assert_normalizes(
        # Multiple functions
        "SELECT COUNT(*), AVG(price) FROM products WHERE created_at > '2023-01-01'" =>
          "SELECT COUNT(*), AVG(price) FROM products WHERE created_at > ?",

        # CASE statements
        "SELECT CASE WHEN age > 18 THEN 'adult' ELSE 'minor' END FROM users" =>
          "SELECT CASE WHEN age > ? THEN ? ELSE ? END FROM users",

        # Window functions
        "SELECT *, ROW_NUMBER() OVER (ORDER BY created_at) FROM posts WHERE user_id = 123" =>
          "SELECT *, ROW_NUMBER() OVER (ORDER BY created_at) FROM posts WHERE user_id = ?",

        # Derived tables are not IN clauses
        "SELECT * FROM t JOIN (SELECT id FROM u WHERE x = 1) s ON s.id = t.id" =>
          "SELECT * FROM t JOIN (SELECT id FROM u WHERE x = ?) s ON s.id = t.id",

        # Non-ASCII values
        "SELECT * FROM t WHERE name = '日本語' AND id = 1" =>
          "SELECT * FROM t WHERE name = ? AND id = ?"
      )
    end

    test "normalize handles BETWEEN clauses" do
      assert_normalizes(
        "SELECT * FROM orders WHERE created_at BETWEEN '2023-01-01' AND '2023-12-31'" =>
          "SELECT * FROM orders WHERE created_at BETWEEN ? AND ?",

        "SELECT * FROM products WHERE price BETWEEN 10.00 AND 100.00" =>
          "SELECT * FROM products WHERE price BETWEEN ? AND ?",

        # Keywords are matched regardless of case
        "select * from t where x between 1 and 2" =>
          "select * from t where x BETWEEN ? AND ?"
      )
    end

    # Identifiers

    test "normalize preserves identifiers with numbers" do
      assert_normalizes(
        # Table names with numbers
        "SELECT * FROM users2 WHERE id = 123" =>
          "SELECT * FROM users2 WHERE id = ?",

        # Column names with numbers
        "SELECT user_id2, created_at FROM posts WHERE user_id2 = 456" =>
          "SELECT user_id2, created_at FROM posts WHERE user_id2 = ?",

        # Schema prefixed tables
        "SELECT * FROM app_v2.users WHERE id = 789" =>
          "SELECT * FROM app_v2.users WHERE id = ?",

        # Quoted identifiers with numbers
        'SELECT "t"."col2" FROM "t" WHERE "t"."col2" = 2' =>
          'SELECT "t"."col2" FROM "t" WHERE "t"."col2" = ?'
      )
    end

    test "normalize leaves identifiers that contain keywords alone" do
      assert_normalizes(
        "SELECT is_true, false_positive FROM t WHERE truly = true" =>
          "SELECT is_true, false_positive FROM t WHERE truly = ?",

        "SELECT in_stock FROM t WHERE in_stock = 1" =>
          "SELECT in_stock FROM t WHERE in_stock = ?",

        # A lone dollar sign is not a string delimiter
        "SELECT * FROM t WHERE price_usd$ > 5" =>
          "SELECT * FROM t WHERE price_usd$ > ?"
      )
    end

    test "normalize replaces double-quoted string values but keeps quoted identifiers" do
      assert_normalizes(
        # Issue #335: a MySQL double-quoted string in the default SQL mode
        'SELECT * FROM users WHERE email = "jane@example.com"' =>
          "SELECT * FROM users WHERE email = ?",

        # Quoted identifiers survive, including a dotted chain in one token
        'SELECT "users"."email" FROM "users" WHERE "users"."id" = 1' =>
          'SELECT "users"."email" FROM "users" WHERE "users"."id" = ?',
        'SELECT "app_v2.users".name FROM "app_v2.users"' =>
          'SELECT "app_v2.users".name FROM "app_v2.users"',

        # A quoted identifier containing a space is indistinguishable from a
        # value and is redacted; Rails never generates one
        'SELECT "user name" FROM "users" WHERE id = 1' =>
          'SELECT ? FROM "users" WHERE id = ?',

        # Quote characters inside a differently quoted span do not open a string
        %(SELECT * FROM t WHERE a = "it's" AND b = 'x') =>
          "SELECT * FROM t WHERE a = ? AND b = ?",
        %(SELECT * FROM t WHERE a = 'say "hi"' AND b = "hi there") =>
          "SELECT * FROM t WHERE a = ? AND b = ?",
        "SELECT `it's` FROM t WHERE a = 'x'" =>
          "SELECT `it's` FROM t WHERE a = ?",

        # A value that happens to look like an internal placeholder
        "SELECT * FROM t WHERE a = '__IDENTIFIER_0__' AND `b` = 1" =>
          "SELECT * FROM t WHERE a = ? AND `b` = ?"
      )
    end

    test "normalize creates distinct queries for different table/column combinations" do
      queries = [
        "SELECT users.* FROM users WHERE users.id = 123",
        "SELECT posts.* FROM posts WHERE posts.id = 123",
        "SELECT users.* FROM users WHERE users.email = 'test@example.com'",
        "SELECT users.name FROM users WHERE users.id = 123"
      ]

      normalized_queries = queries.map { |q| RailsPulse::SqlQueryNormalizer.normalize(q) }

      assert_equal queries.length, normalized_queries.uniq.length,
        "Expected all normalized queries to be unique: #{normalized_queries}"
    end

    # IN Clauses

    test "normalize collapses IN lists regardless of length" do
      assert_normalizes(
        # Simple IN clause
        "SELECT * FROM users WHERE id IN (1, 2, 3)" =>
          "SELECT * FROM users WHERE id IN (?)",

        # IN clause with strings
        "SELECT * FROM users WHERE status IN ('active', 'pending', 'inactive')" =>
          "SELECT * FROM users WHERE status IN (?)",

        # Single value IN clause
        "SELECT * FROM users WHERE id IN (123)" =>
          "SELECT * FROM users WHERE id IN (?)",

        # Several IN clauses in one statement
        "SELECT * FROM events WHERE type IN ('login', 'logout') AND user_id IN (1, 2)" =>
          "SELECT * FROM events WHERE type IN (?) AND user_id IN (?)",

        # NOT IN, no space before the paren, lower case
        "SELECT * FROM t WHERE id NOT IN (1, 2)" =>
          "SELECT * FROM t WHERE id NOT IN (?)",
        "SELECT * FROM t WHERE id IN(1,2,3)" =>
          "SELECT * FROM t WHERE id IN (?)",
        "select * from t where id in (1, 2)" =>
          "select * from t where id IN (?)",

        # Expressions in the list are values too
        "SELECT * FROM t WHERE x IN (LOWER('a'), LOWER('b'))" =>
          "SELECT * FROM t WHERE x IN (?)"
      )
    end

    test "normalize gives a preload the same fingerprint however many ids it loads" do
      fingerprints = [ 1, 3, 12 ].map do |count|
        ids = (1..count).to_a.join(", ")
        RailsPulse::SqlQueryNormalizer.normalize(%(SELECT "posts".* FROM "posts" WHERE "posts"."user_id" IN (#{ids})), adapter: "postgresql")
      end

      assert_equal 1, fingerprints.uniq.length, fingerprints.inspect
    end

    test "normalize keeps IN subqueries and normalizes inside them" do
      assert_normalizes(
        # Simple subquery
        "SELECT * FROM users WHERE id IN (SELECT user_id FROM posts)" =>
          "SELECT * FROM users WHERE id IN (SELECT user_id FROM posts)",

        # Nested parens inside the subquery must not end the IN clause early
        'SELECT 1 AS one FROM "posts" WHERE "posts"."id" IN (SELECT "comments"."post_id" FROM "comments" GROUP BY "comments"."post_id" HAVING (COUNT(*) > 2)) LIMIT 1' =>
          'SELECT ? AS one FROM "posts" WHERE "posts"."id" IN (SELECT "comments"."post_id" FROM "comments" GROUP BY "comments"."post_id" HAVING (COUNT(*) > ?)) LIMIT ?',

        # Subquery with multiple levels of nesting
        "SELECT * FROM users WHERE id IN (SELECT user_id FROM posts WHERE id IN (SELECT post_id FROM comments)) LIMIT 10" =>
          "SELECT * FROM users WHERE id IN (SELECT user_id FROM posts WHERE id IN (SELECT post_id FROM comments)) LIMIT ?",

        # A literal list inside the subquery collapses like any other
        "SELECT * FROM users WHERE id IN (SELECT user_id FROM posts WHERE status IN ('a', 'b', 'c'))" =>
          "SELECT * FROM users WHERE id IN (SELECT user_id FROM posts WHERE status IN (?))",

        # Subqueries that do not start with SELECT
        "SELECT * FROM t WHERE id IN ((SELECT id FROM u))" =>
          "SELECT * FROM t WHERE id IN ((SELECT id FROM u))",
        "SELECT * FROM t WHERE id IN (WITH x AS (SELECT 1) SELECT * FROM x)" =>
          "SELECT * FROM t WHERE id IN (WITH x AS (SELECT ?) SELECT * FROM x)"
      )
    end

    test "normalize keeps a list and a subquery as different statements" do
      list = RailsPulse::SqlQueryNormalizer.normalize("SELECT * FROM users WHERE id IN (1, 2)")
      subquery = RailsPulse::SqlQueryNormalizer.normalize("SELECT * FROM users WHERE id IN (SELECT user_id FROM posts)")

      assert_not_equal list, subquery
    end

    test "normalize handles malformed IN clauses without raising" do
      assert_normalizes(
        "SELECT * FROM t WHERE id IN ()" =>
          "SELECT * FROM t WHERE id IN (?)",
        "SELECT * FROM t WHERE id IN (1, 2" =>
          "SELECT * FROM t WHERE id IN (?)"
      )
    end

    # VALUES Rows

    test "normalize keeps one row of a multi-row insert" do
      assert_normalizes(
        # insert_all on PostgreSQL
        'INSERT INTO "users" ("name", "age") VALUES (\'Jane\', 30), (\'Bob\', 25), (\'Ann\', 41) ON CONFLICT DO NOTHING RETURNING "id"' =>
          'INSERT INTO "users" ("name", "age") VALUES (?, ?) ON CONFLICT DO NOTHING RETURNING "id"',

        # upsert_all on MySQL, where VALUES(col) is also a function
        "INSERT INTO `users` (`name`, `age`) VALUES ('Jane', 30),('Bob', 25) ON DUPLICATE KEY UPDATE `age`=VALUES(`age`)" =>
          "INSERT INTO `users` (`name`, `age`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `age`=VALUES(`age`)",

        # Rows containing nested parens
        "INSERT INTO t (a, b) VALUES (1, COALESCE(2, 3)), (4, COALESCE(5, 6))" =>
          "INSERT INTO t (a, b) VALUES (?, COALESCE(?, ?))",

        # A single row is unchanged
        "INSERT INTO t (a, b) VALUES (1, 2)" =>
          "INSERT INTO t (a, b) VALUES (?, ?)",

        # An unterminated row does not raise
        "INSERT INTO t (a, b) VALUES (1, 2), (3" =>
          "INSERT INTO t (a, b) VALUES (?, ?)"
      )
    end

    test "normalize gives a batch insert the same fingerprint however many rows it writes" do
      fingerprints = [ 1, 2, 50 ].map do |count|
        rows = (1..count).map { |n| "(#{n}, 'name #{n}')" }.join(", ")
        RailsPulse::SqlQueryNormalizer.normalize(%(INSERT INTO "users" ("id", "name") VALUES #{rows}), adapter: "postgresql")
      end

      assert_equal 1, fingerprints.uniq.length, fingerprints.inspect
    end

    # Dialects

    test "normalize handles various SQL dialects" do
      assert_normalizes(
        # PostgreSQL style
        'SELECT "users"."name" FROM "users" WHERE "users"."id" = 123' =>
          'SELECT "users"."name" FROM "users" WHERE "users"."id" = ?',

        # MySQL style
        "SELECT `users`.`name` FROM `users` WHERE `users`.`id` = 123" =>
          "SELECT `users`.`name` FROM `users` WHERE `users`.`id` = ?",

        # Mixed quoting
        'SELECT `user_id`, "created_at" FROM user_sessions WHERE active = true' =>
          'SELECT `user_id`, "created_at" FROM user_sessions WHERE active = ?',

        # MySQL character set introducer
        "SELECT * FROM t WHERE a = _utf8mb4'abc'" =>
          "SELECT * FROM t WHERE a = _utf8mb4?"
      )
    end

    test "normalize keeps PostgreSQL bind placeholders recognisable" do
      # With prepared statements the SQL arrives with $1-style binds rather
      # than values. They normalize to $? rather than ?, and that form is
      # stored on every PostgreSQL install, so changing it would split each
      # query's history across two entries.
      assert_normalizes(
        'SELECT "users".* FROM "users" WHERE "users"."id" = $1 LIMIT $2' =>
          'SELECT "users".* FROM "users" WHERE "users"."id" = $? LIMIT $?',
        # An IN list collapses whatever it holds
        "SELECT * FROM t WHERE id IN ($1, $2, $3)" =>
          "SELECT * FROM t WHERE id IN (?)"
      )
    end

    test "normalize replaces backslash-escaped quotes on MySQL adapters" do
      %w[mysql2 trilogy Mysql2 Trilogy].each do |adapter|
        assert_normalizes({
          # Issue #335: mysql2 and trilogy escape a quote as \' rather than ''
          "SELECT * FROM users WHERE name = 'O\\'Brien' AND email = 'x@y.com'" =>
            "SELECT * FROM users WHERE name = ? AND email = ?",
          %(SELECT * FROM users WHERE name = "O\\"Brien" AND email = "x@y.com") =>
            "SELECT * FROM users WHERE name = ? AND email = ?",

          # An escaped backslash does not escape the closing quote
          "SELECT * FROM t WHERE p = 'C:\\\\' AND b = 'x'" =>
            "SELECT * FROM t WHERE p = ? AND b = ?",

          # Doubled quotes are still an escape
          "SELECT * FROM t WHERE name = 'O''Brien' AND b = 'x'" =>
            "SELECT * FROM t WHERE name = ? AND b = ?",

          # Backticked identifiers never use backslash escapes
          "SELECT `a\\` FROM t WHERE b = 'x'" =>
            "SELECT `a\\` FROM t WHERE b = ?",

          # LIKE with an escape clause, as MySQL spells it
          "SELECT * FROM t WHERE a LIKE '%foo\\\\%' ESCAPE '\\\\'" =>
            "SELECT * FROM t WHERE a LIKE ? ESCAPE ?"
        }, adapter)
      end
    end

    test "normalize redacts every double-quoted span on MySQL adapters" do
      %w[mysql2 trilogy].each do |adapter|
        assert_normalizes({
          # Issue #313: on MySQL double quotes delimit a string, so a value
          # that happens to be shaped like an identifier is still a value
          %(SELECT * FROM users WHERE name = "JaneDoe" AND phone = "5551234567" AND note = 'Jane Doe' AND id = 123) =>
            "SELECT * FROM users WHERE name = ? AND phone = ? AND note = ? AND id = ?",

          # Rails quotes MySQL identifiers with backticks, never double quotes
          'SELECT `user_id`, "created_at" FROM `user_sessions`' =>
            "SELECT `user_id`, ? FROM `user_sessions`"
        }, adapter)
      end
    end

    test "normalize treats a backslash as an ordinary character on other adapters" do
      %w[postgresql sqlite3].each do |adapter|
        assert_normalizes({
          # A string ending in a backslash is complete on these databases
          "SELECT * FROM t WHERE p = 'C:\\' AND b = 'x'" =>
            "SELECT * FROM t WHERE p = ? AND b = ?",
          %(SELECT * FROM t WHERE p = "C:\\" AND b = "a b") =>
            "SELECT * FROM t WHERE p = ? AND b = ?",

          # LIKE with an escape clause, as these databases spell it
          "SELECT * FROM t WHERE a LIKE '%foo\\%' ESCAPE '\\'" =>
            "SELECT * FROM t WHERE a LIKE ? ESCAPE ?",

          # Double quotes delimit identifiers here, so an identifier-shaped
          # token is kept even on the right of a comparison; Rails never
          # writes a value that way on these databases (issue #313)
          'SELECT * FROM users WHERE name = "JaneDoe" AND phone = "5551234567"' =>
            'SELECT * FROM users WHERE name = "JaneDoe" AND phone = ?'
        }, adapter)
      end
    end

    test "normalize redacts a value quoted by the host's own adapter" do
      value = ActiveRecord::Base.connection.quote("O'Brien said \"hi\" \\ bye")
      query = "SELECT * FROM users WHERE name = #{value} AND email = 'x@y.com'"

      assert_equal "SELECT * FROM users WHERE name = ? AND email = ?",
        RailsPulse::SqlQueryNormalizer.normalize(query)
    end

    test "normalize replaces dollar-quoted string literals" do
      assert_normalizes(
        # Issue #335: dollar-quoted values must not survive normalization
        "SELECT * FROM notes WHERE body = $$jane@example.com$$" =>
          "SELECT * FROM notes WHERE body = ?",

        # Tagged form, spanning lines and containing single quotes
        "SELECT * FROM notes WHERE body = $tag$line one\nit's 'quoted'$tag$ AND id = 7" =>
          "SELECT * FROM notes WHERE body = ? AND id = ?",

        # Content containing every other quote form
        %(SELECT * FROM notes WHERE body = $$it's a "quoted" `word`$$) =>
          "SELECT * FROM notes WHERE body = ?",

        # Two dollar-quoted values stay two values
        "SELECT * FROM t WHERE a = $$x$$ AND b = $$y$$" =>
          "SELECT * FROM t WHERE a = ? AND b = ?",

        # A differently tagged delimiter inside the string is content
        "SELECT * FROM t WHERE a = $a$ x $b$ y $b$ z $a$ AND b = 1" =>
          "SELECT * FROM t WHERE a = ? AND b = ?",

        # $$ inside an ordinary string is part of that string, not an opener
        "SELECT * FROM t WHERE a = '$$' AND b = 'x'" =>
          "SELECT * FROM t WHERE a = ? AND b = ?",

        # An unterminated opener is left alone
        "SELECT * FROM t WHERE a = $$oops AND b = 1" =>
          "SELECT * FROM t WHERE a = $$oops AND b = ?"
      )
    end

    test "normalize replaces prefixed string literals" do
      assert_normalizes(
        # Issue #335: PostgreSQL escape string with a backslash-escaped quote
        "SELECT * FROM users WHERE email = E'jane\\'s@example.com'" =>
          "SELECT * FROM users WHERE email = ?",

        # Lower-case prefix with a doubled-quote escape
        "SELECT * FROM users WHERE name = e'O''Brien'" =>
          "SELECT * FROM users WHERE name = ?",

        # Bit, hex and national strings
        "SELECT * FROM flags WHERE bits = B'1010' AND hex = X'4F' AND label = N'value'" =>
          "SELECT * FROM flags WHERE bits = ? AND hex = ? AND label = ?",

        # A value that is just the letter E must not act as a prefix for
        # whatever follows the next quote
        "SELECT * FROM grades WHERE grade = 'E' AND name = 'Jane'" =>
          "SELECT * FROM grades WHERE grade = ? AND name = ?"
      )
    end

    # Edge Cases

    test "normalize handles edge cases gracefully" do
      assert_nil RailsPulse::SqlQueryNormalizer.normalize(nil)

      assert_normalizes(
        "" => "",

        # Already normalized query
        "SELECT * FROM users WHERE id = ?" =>
          "SELECT * FROM users WHERE id = ?",

        # Multiple whitespace normalization
        "SELECT   *    FROM   users   WHERE  id = 123" =>
          "SELECT * FROM users WHERE id = ?",
        "SELECT *\n\tFROM users\n WHERE id = 1" =>
          "SELECT * FROM users WHERE id = ?",

        # Trailing semicolon
        "SELECT * FROM users WHERE id = 1;" =>
          "SELECT * FROM users WHERE id = ?;",

        # PostgreSQL's jsonb ? operator survives alongside placeholders
        "SELECT * FROM t WHERE data ? 'key' AND id = 1" =>
          "SELECT * FROM t WHERE data ? ? AND id = ?"
      )
    end

    # Performance

    test "normalize handles long literals of every quote form under a tight Regexp.timeout" do
      skip "Regexp.timeout requires Ruby 3.2+" unless Regexp.respond_to?(:timeout=)

      long_value = "x" * 2_000_000
      queries = {
        "SELECT * FROM logs WHERE message = '#{long_value}'" =>
          "SELECT * FROM logs WHERE message = ?",
        "SELECT * FROM logs WHERE a = $$#{long_value}$$ AND b = E'#{long_value}\\' tail'" =>
          "SELECT * FROM logs WHERE a = ? AND b = ?",
        "SELECT * FROM logs WHERE a = \"#{long_value}\" AND b = 1" =>
          "SELECT * FROM logs WHERE a = ? AND b = ?",
        "SELECT `#{long_value}` FROM logs WHERE b = 1" =>
          "SELECT `#{long_value}` FROM logs WHERE b = ?"
      }

      original_timeout = Regexp.timeout
      begin
        Regexp.timeout = 0.05

        queries.each do |query, expected|
          assert_equal expected, RailsPulse::SqlQueryNormalizer.normalize(query)
        end
      ensure
        Regexp.timeout = original_timeout
      end
    end

    test "normalize completes quickly on strings with many unpaired quotes" do
      pathological_value = "'" * 200_000
      query = "SELECT * FROM logs WHERE message = #{pathological_value}"

      result = nil
      elapsed = Benchmark.realtime do
        result = RailsPulse::SqlQueryNormalizer.normalize(query)
      end

      assert_operator elapsed, :<, 1, "normalize took too long (#{elapsed}s) on pathological input"
      assert_kind_of String, result
    end

    test "normalize completes quickly on a long unterminated string literal" do
      long_unterminated = "SELECT * FROM logs WHERE message = 'unterminated #{"x" * 200_000}"

      result = nil
      elapsed = Benchmark.realtime do
        result = RailsPulse::SqlQueryNormalizer.normalize(long_unterminated)
      end

      assert_operator elapsed, :<, 1, "normalize took too long (#{elapsed}s) on unterminated literal"
      assert_kind_of String, result
    end

    test "normalize completes quickly on a very large IN list" do
      ids = (1..100_000).to_a.join(", ")
      query = "SELECT \"users\".* FROM \"users\" WHERE \"users\".\"id\" IN (#{ids})"

      result = nil
      elapsed = Benchmark.realtime do
        result = RailsPulse::SqlQueryNormalizer.normalize(query, adapter: "postgresql")
      end

      assert_operator elapsed, :<, 2, "normalize took too long (#{elapsed}s) on a large IN list"
      assert_equal 'SELECT "users".* FROM "users" WHERE "users"."id" IN (?)', result
    end

    private

    # Examples name their dialect so they do not change meaning with the
    # database the suite happens to run against; the host default is
    # covered by the tests that call normalize without an adapter.
    def assert_normalizes(examples, adapter = "postgresql")
      examples.each do |input, expected|
        result = RailsPulse::SqlQueryNormalizer.normalize(input, adapter: adapter)

        assert_equal expected, result, "Failed for input: #{input.inspect} (adapter: #{adapter})"
      end
    end
  end
end
