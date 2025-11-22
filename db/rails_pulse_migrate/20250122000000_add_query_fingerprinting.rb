# frozen_string_literal: true

# Add query fingerprinting to handle long SQL queries
# Uses MD5 hash of normalized SQL as unique identifier
class AddQueryFingerprinting < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:rails_pulse_queries)

    # Add hashed_sql column if it doesn't exist
    unless column_exists?(:rails_pulse_queries, :hashed_sql)
      say "Adding hashed_sql column to rails_pulse_queries..."
      add_column :rails_pulse_queries, :hashed_sql, :string, limit: 32

      # Backfill existing records with MD5 hash
      say "Backfilling query hashes for existing records..."
      backfill_query_hashes

      # Make it required and unique
      say "Adding constraints and indexes..."
      change_column_null :rails_pulse_queries, :hashed_sql, false
      add_index :rails_pulse_queries, :hashed_sql, unique: true,
                name: "index_rails_pulse_queries_on_hashed_sql"

      # Remove old index
      say "Removing old normalized_sql index..."
      if index_exists?(:rails_pulse_queries, :normalized_sql, name: "index_rails_pulse_queries_on_normalized_sql")
        remove_index :rails_pulse_queries, :normalized_sql, name: "index_rails_pulse_queries_on_normalized_sql"
      end

      # Change normalized_sql to text (remove 1000 char limit)
      say "Changing normalized_sql to text type (removing length limit)..."
      change_column :rails_pulse_queries, :normalized_sql, :text

      say "Query fingerprinting migration completed successfully!", :green
    else
      say "Query fingerprinting already applied. Skipping.", :yellow
    end
  end

  def down
    # Prevent rollback if there are queries longer than 1000 characters
    if has_long_queries?
      raise ActiveRecord::IrreversibleMigration,
            "Cannot rollback: normalized_sql contains queries longer than 1000 characters. " \
            "Rolling back would truncate data."
    end

    return unless column_exists?(:rails_pulse_queries, :hashed_sql)

    say "Rolling back query fingerprinting changes..."

    # Restore varchar limit (safe because we checked for long queries)
    change_column :rails_pulse_queries, :normalized_sql, :string, limit: 1000

    # Restore old index
    add_index :rails_pulse_queries, :normalized_sql, unique: true,
              name: "index_rails_pulse_queries_on_normalized_sql", length: 191

    # Remove new index
    if index_exists?(:rails_pulse_queries, :hashed_sql, name: "index_rails_pulse_queries_on_hashed_sql")
      remove_index :rails_pulse_queries, :hashed_sql, name: "index_rails_pulse_queries_on_hashed_sql"
    end

    # Remove hashed_sql column
    remove_column :rails_pulse_queries, :hashed_sql

    say "Rollback completed.", :green
  end

  private

  def backfill_query_hashes
    adapter = connection.adapter_name.downcase

    if adapter.include?("postgres") || adapter.include?("mysql")
      # Use database MD5 function for better performance
      execute <<-SQL
        UPDATE rails_pulse_queries
        SET hashed_sql = MD5(normalized_sql)
        WHERE hashed_sql IS NULL
      SQL
    else
      # SQLite - use Ruby MD5 (slower but works)
      require "digest"
      RailsPulse::Query.where(hashed_sql: nil).find_each do |query|
        query.update_column(:hashed_sql, Digest::MD5.hexdigest(query.normalized_sql))
      end
    end

    # Handle potential duplicates (queries with same normalized SQL)
    handle_duplicate_hashes
  end

  def handle_duplicate_hashes
    # Group queries by hash and find duplicates
    query_groups = RailsPulse::Query
      .select(:hashed_sql)
      .group(:hashed_sql)
      .having("COUNT(*) > 1")
      .pluck(:hashed_sql)

    return if query_groups.empty?

    say "Found #{query_groups.size} duplicate query groups. Merging...", :yellow

    query_groups.each do |hash|
      # Get all queries with this hash, ordered by creation time
      queries = RailsPulse::Query.where(hashed_sql: hash).order(:created_at).to_a
      keep_query = queries.first
      duplicate_queries = queries[1..]

      duplicate_queries.each do |dup_query|
        # Count operations before merge
        operations_count = RailsPulse::Operation.where(query_id: dup_query.id).count

        if operations_count > 0
          say "  Merging #{operations_count} operations from query ##{dup_query.id} into ##{keep_query.id}"

          # Reassign operations to the kept query
          RailsPulse::Operation.where(query_id: dup_query.id).update_all(query_id: keep_query.id)
        end

        # Delete the duplicate query
        dup_query.delete
      end
    end

    say "Merged #{query_groups.size} duplicate query groups successfully.", :green
  end

  def has_long_queries?
    # Check if any queries exceed 1000 characters
    adapter = connection.adapter_name.downcase

    if adapter.include?("postgres")
      result = execute("SELECT EXISTS(SELECT 1 FROM rails_pulse_queries WHERE LENGTH(normalized_sql) > 1000)")
      # Handle both Rails 7.2 and 8.0 result formats
      result.first.is_a?(Hash) ? result.first["exists"] == "t" : result.first[0] == "t"
    elsif adapter.include?("mysql")
      result = execute("SELECT EXISTS(SELECT 1 FROM rails_pulse_queries WHERE LENGTH(normalized_sql) > 1000) as result")
      # Handle both result formats
      result.first.is_a?(Hash) ? result.first["result"] == 1 : result.first[0] == 1
    else
      # SQLite
      result = execute("SELECT COUNT(*) as count FROM rails_pulse_queries WHERE LENGTH(normalized_sql) > 1000")
      count = result.first.is_a?(Hash) ? result.first["count"] : result.first[0]
      count.to_i > 0
    end
  end
end
