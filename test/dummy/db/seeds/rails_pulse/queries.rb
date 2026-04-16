require "digest"

module RailsPulse
  module Seeds
    module Queries
      # Mix of good and problematic queries for analysis
      QUERIES = [
        # Good queries
        "SELECT id, name, email FROM users WHERE id = ?",
        "SELECT * FROM posts WHERE user_id = ? ORDER BY created_at DESC LIMIT ?",
        "SELECT posts.title, posts.content, users.name FROM posts JOIN users ON posts.user_id = users.id WHERE posts.published = ?",
        "SELECT COUNT(*) FROM comments WHERE post_id = ?",
        "SELECT * FROM comments WHERE post_id = ? ORDER BY created_at DESC LIMIT ?",
        "INSERT INTO posts (user_id, title, content, published, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        "UPDATE posts SET title = ?, content = ?, updated_at = ? WHERE id = ?",
        "DELETE FROM posts WHERE id = ?",
        "SELECT id, name FROM users WHERE email = ?",

        # Problematic queries for analysis (will trigger issues and suggestions)
        "SELECT * FROM users WHERE id = ?",  # SELECT * issue
        "SELECT name FROM users",  # Missing WHERE clause
        "SELECT posts.* FROM posts WHERE title LIKE ? OR content LIKE ?",  # Missing LIMIT on search
        "SELECT * FROM posts WHERE created_at > ?",  # SELECT * + Missing LIMIT
        "SELECT users.* FROM users LEFT JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON posts.id = comments.post_id WHERE users.active = ? AND posts.published = ? AND comments.approved = ? OR users.created_at > ? AND posts.created_at > ? AND comments.created_at > ?",  # Complex WHERE clause

        # Very complex queries that will trigger multiple issues
        "SELECT * FROM users LEFT JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON posts.id = comments.post_id LEFT JOIN tags ON posts.id = tags.post_id LEFT JOIN categories ON posts.category_id = categories.id WHERE users.active = ? AND posts.published = ? AND comments.approved = ? AND tags.name LIKE ? AND categories.visible = ? AND users.email LIKE ? AND posts.title LIKE ? OR comments.content LIKE ? AND users.created_at BETWEEN ? AND ? AND posts.updated_at > ? ORDER BY users.created_at, posts.created_at, comments.created_at",  # SELECT *, many JOINs, complex WHERE, no LIMIT

        "SELECT users.*, posts.*, comments.*, COUNT(DISTINCT posts.id) as post_count, COUNT(DISTINCT comments.id) as comment_count, AVG(posts.view_count) as avg_views, MAX(comments.created_at) as latest_comment FROM users LEFT JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON users.id = comments.user_id LEFT JOIN user_preferences ON users.id = user_preferences.user_id LEFT JOIN subscriptions ON users.id = subscriptions.user_id WHERE (users.active = ? OR users.premium = ?) AND (posts.published = ? OR posts.featured = ?) AND (comments.approved = ? OR comments.flagged = ?) AND users.created_at BETWEEN ? AND ? GROUP BY users.id HAVING COUNT(posts.id) > ? AND AVG(posts.view_count) > ?",  # Very complex with subqueries, aggregations, HAVING

        "SELECT * FROM (SELECT users.id, users.name, users.email, COUNT(posts.id) as post_count FROM users LEFT JOIN posts ON users.id = posts.user_id WHERE users.active = ? GROUP BY users.id) as user_posts JOIN (SELECT user_id, COUNT(*) as comment_count FROM comments WHERE approved = ? GROUP BY user_id) as user_comments ON user_posts.id = user_comments.user_id WHERE user_posts.post_count > ? AND user_comments.comment_count > ?",  # Subqueries, SELECT *

        "SELECT DISTINCT users.*, posts.*, comments.* FROM users, posts, comments WHERE users.id = posts.user_id AND posts.id = comments.post_id AND users.created_at > ? AND posts.created_at > ? AND comments.created_at > ?",  # Old-style JOINs, SELECT *, DISTINCT without LIMIT

        # Aggregation heavy queries
        "SELECT users.*, COUNT(DISTINCT posts.id) as post_count, COUNT(DISTINCT comments.id) as comment_count, SUM(posts.view_count) as total_views, AVG(posts.view_count) as avg_views, MIN(posts.created_at) as first_post, MAX(posts.created_at) as latest_post FROM users LEFT JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON users.id = comments.user_id GROUP BY users.id",  # Missing WHERE, many aggregations

        # Search queries without proper indexing considerations
        "SELECT * FROM posts WHERE title LIKE ? AND content LIKE ? AND LOWER(title) LIKE ? AND UPPER(content) LIKE ?",  # Function calls in WHERE, SELECT *, no LIMIT

        # Update/Delete without proper constraints
        "UPDATE posts SET view_count = view_count + 1 WHERE published = ?",  # Potentially updates many rows
        "DELETE FROM comments WHERE created_at < ?"  # Potentially deletes many rows
      ].freeze

      def self.seed!
        QUERIES.map do |sql|
          normalized = ::RailsPulse::SqlQueryNormalizer.normalize(sql)
          ::RailsPulse::Query.find_or_create_by!(hashed_sql: Digest::MD5.hexdigest(normalized)) do |q|
            q.normalized_sql = normalized
          end
        end
      end
    end
  end
end
