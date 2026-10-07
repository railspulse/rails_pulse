require "test_helper"

module RailsPulse
  module Cloud
    class QueryShapeTest < ActiveSupport::TestCase
      # Structure Tests

      # The examples in the sync contract's "Rule: SQL", including the three
      # literals normalisation is known to leave in place.
      [
        [ 'SELECT "users".* FROM "users" WHERE "users"."email" = ? LIMIT ?',
          "SELECT users.* FROM users WHERE users.email = ? LIMIT ?", "SELECT users" ],
        [ 'SELECT "posts".* FROM "posts" INNER JOIN "comments" ON "comments"."post_id" = "posts"."id" WHERE "posts"."published" = ? ORDER BY "posts"."created_at" DESC LIMIT ?',
          "SELECT posts.* FROM posts INNER JOIN comments ON comments.post_id = posts.id WHERE posts.published = ? ORDER BY posts.created_at DESC LIMIT ?",
          "SELECT posts, comments" ],
        [ 'UPDATE "subscriptions" SET "status" = ?, "updated_at" = ? WHERE "subscriptions"."id" = ?',
          "UPDATE subscriptions SET status = ?, updated_at = ? WHERE subscriptions.id = ?", "UPDATE subscriptions" ],
        [ 'SELECT "invoices".* FROM "acme_corp"."invoices" WHERE "invoices"."id" = ?',
          "SELECT invoices.* FROM invoices WHERE invoices.id = ?", "SELECT invoices" ],
        [ "SELECT * FROM notes WHERE body = $$jane@example.com$$", nil, "SELECT notes" ],
        [ "SELECT * FROM users WHERE email = E?s@example.com'", nil, "SELECT users" ],
        [ 'SELECT * FROM users WHERE email = "jane@example.com"', nil, "SELECT users" ]
      ].each do |stored, sql_shape, label|
        test "builds the contract's shape and label for #{stored.truncate(60)}" do
          shape = QueryShape.new(stored)

          if sql_shape
            assert_equal sql_shape, shape.sql_shape
          else
            assert_nil shape.sql_shape
          end

          assert_equal label, shape.label
        end
      end

      # Calculation Tests

      test "numbers become placeholders" do
        assert_equal "SELECT users.* FROM users LIMIT ? OFFSET ?", QueryShape.new("SELECT users.* FROM users LIMIT 10 OFFSET 2.5").sql_shape
      end

      test "numbered bind parameters become placeholders" do
        assert_equal "SELECT * FROM users WHERE id = ?", QueryShape.new("SELECT * FROM users WHERE id = $1").sql_shape
      end

      test "function calls and lists keep their parentheses tight" do
        assert_equal "SELECT COUNT(*) FROM users WHERE id IN (?, ?)", QueryShape.new("SELECT COUNT(*) FROM users WHERE id IN (?, ?)").sql_shape
      end

      test "a table's column list keeps its space from the table name" do
        assert_equal "INSERT INTO posts (title, body) VALUES (?, ?)", QueryShape.new("INSERT INTO posts(title, body) VALUES (?, ?)").sql_shape
      end

      test "a three-part name loses its schema anywhere" do
        assert_equal "SELECT invoices.id FROM invoices", QueryShape.new('SELECT "acme"."invoices"."id" FROM "acme"."invoices"').sql_shape
      end

      test "comments are dropped, so query log tags do not reach the shape" do
        sql = "SELECT * FROM users /*application:Shop,request_id:4f1a-77*/ WHERE id = ? -- trailing note"

        assert_equal "SELECT * FROM users WHERE id = ?", QueryShape.new(sql).sql_shape
      end

      test "a single-quoted string is never allowed" do
        assert_nil QueryShape.new("SELECT * FROM users WHERE name = 'jane'").sql_shape
      end

      test "on MySQL a double-quoted token is a string even when it reads like a name" do
        sql = 'SELECT * FROM `users` WHERE name = "jane"'

        assert_nil QueryShape.for_adapter(sql, "mysql2").sql_shape
        assert_nil QueryShape.for_adapter(sql, "trilogy").sql_shape
        assert_equal "SELECT * FROM users WHERE name = jane", QueryShape.for_adapter(sql, "postgresql").sql_shape
      end

      test "backtick identifiers are unquoted" do
        assert_equal "SELECT users.id FROM users", QueryShape.for_adapter("SELECT `users`.`id` FROM `users`", "mysql2").sql_shape
      end

      test "the label lists at most five tables, each once" do
        sql = "SELECT * FROM a JOIN b ON ? JOIN c ON ? JOIN d ON ? JOIN e ON ? JOIN f ON ? JOIN a ON ?"

        assert_equal "SELECT a, b, c, d, e", QueryShape.new(sql).label
      end

      test "the label is built for an INSERT and a DELETE" do
        assert_equal "INSERT users", QueryShape.new('INSERT INTO "users" ("name") VALUES (?)').label
        assert_equal "DELETE sessions", QueryShape.new("DELETE FROM sessions WHERE id = ?").label
      end

      test "the shape is truncated to 2,000 characters" do
        sql = "SELECT #{(1..600).map { |n| "column_#{n}" }.join(', ')} FROM wide"

        assert_equal QueryShape::MAX_LENGTH, QueryShape.new(sql).sql_shape.length
      end

      # Edge Cases

      test "a subquery after FROM is not taken for a table" do
        assert_equal "SELECT", QueryShape.new("SELECT * FROM (SELECT ? AS one) AS t").label
      end

      test "a query that starts with something unsafe is labelled QUERY" do
        shape = QueryShape.new("'oops' FROM users")

        assert_nil shape.sql_shape
        assert_equal "QUERY users", shape.label
      end

      test "an unterminated quoted identifier is unsafe" do
        assert_nil QueryShape.new('SELECT * FROM "users').sql_shape
      end

      test "an empty or nil query has an empty shape and a QUERY label" do
        assert_equal "", QueryShape.new(nil).sql_shape
        assert_equal "QUERY", QueryShape.new("").label
      end
    end
  end
end
