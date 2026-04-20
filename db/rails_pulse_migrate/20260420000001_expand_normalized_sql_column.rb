class ExpandNormalizedSqlColumn < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:rails_pulse_queries)

    adapter = connection.adapter_name.downcase

    # SQLite doesn't enforce string length limits, so no migration needed there.
    # change_column is also not supported on SQLite.
    return unless adapter.include?("postgresql") || adapter.include?("mysql")

    column = connection.columns(:rails_pulse_queries).find { |c| c.name == "normalized_sql" }
    return unless column

    # Only migrate if the column is still a limited string type (not already text)
    return unless column.type == :string

    change_column :rails_pulse_queries, :normalized_sql, :text, null: false
  end

  def down
    return unless table_exists?(:rails_pulse_queries)

    adapter = connection.adapter_name.downcase
    return unless adapter.include?("postgresql") || adapter.include?("mysql")

    change_column :rails_pulse_queries, :normalized_sql, :string, limit: 1000, null: false
  end
end
