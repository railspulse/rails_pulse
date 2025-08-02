class CreateQueries < RailsPulse::Migration
  def change
    create_table :rails_pulse_queries do |t|
      # Use string with reasonable limit instead of text to avoid MySQL index length issues
      # 1000 characters should be sufficient for most normalized SQL queries
      t.string :normalized_sql, limit: 1000, null: false, comment: "Normalized SQL query string (e.g., SELECT * FROM users WHERE id = ?)"

      t.timestamps
    end

    # Now using string instead of text, no need for database-specific logic
    add_index :rails_pulse_queries, :normalized_sql, unique: true, name: "index_rails_pulse_queries_on_normalized_sql", length: 191
  end
end
