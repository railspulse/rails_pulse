class CreateOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :rails_pulse_operations do |t|
      t.references :request, null: false, foreign_key: { to_table: :rails_pulse_requests }, comment: "Link to the request"
      t.references :query, foreign_key: { to_table: :rails_pulse_queries }, index: true, comment: "Link to the normalized SQL query"
      t.string :operation_type, null: false, comment: "Type of operation (e.g., database, view, gem_call)"
      t.string :label, null: false, comment: "Descriptive name (e.g., SELECT FROM users WHERE id = 1, render layout)"
      t.decimal :duration, precision: 10, scale: 6, null: false, comment: "Operation duration in milliseconds"
      t.string :codebase_location, comment: "File and line number (e.g., app/models/user.rb:25)"
      t.float :start_time, null: false, default: 0.0, comment: "Operation start time in milliseconds"
      t.timestamp :occurred_at, null: false, comment: "When the request started"

      t.timestamps
    end

    # add_index :rails_pulse_operations, :request_id, name: 'index_rails_pulse_operations_on_request_id'
    add_index :rails_pulse_operations, :operation_type, name: 'index_rails_pulse_operations_on_operation_type'
  end
end
