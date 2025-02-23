class CreateQueries < ActiveRecord::Migration[8.0]
  def change
    create_table :rails_pulse_queries do |t|
      t.text :normalized_sql, null: false, comment: "Normalized SQL query string (e.g., SELECT * FROM users WHERE id = ?)"

      t.timestamps
    end

    add_index :rails_pulse_queries, :normalized_sql, unique: true, name: "index_rails_pulse_queries_on_normalized_sql"
  end
end
