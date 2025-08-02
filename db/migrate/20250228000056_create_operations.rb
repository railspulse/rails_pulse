class CreateOperations < RailsPulse::Migration
  def change
    create_table :rails_pulse_operations do |t|
      t.references :request, null: false, foreign_key: { to_table: :rails_pulse_requests }, comment: "Link to the request"
      t.references :query, foreign_key: { to_table: :rails_pulse_queries }, index: true, comment: "Link to the normalized SQL query"
      t.string :operation_type, null: false, comment: "Type of operation (e.g., database, view, gem_call)"
      t.string :label, null: false, comment: "Descriptive name (e.g., SELECT FROM users WHERE id = 1, render layout)"
      t.decimal :duration, precision: 15, scale: 6, null: false, comment: "Operation duration in milliseconds"
      t.string :codebase_location, comment: "File and line number (e.g., app/models/user.rb:25)"
      t.float :start_time, null: false, default: 0.0, comment: "Operation start time in milliseconds"
      t.timestamp :occurred_at, null: false, comment: "When the request started"

      t.timestamps
    end

    add_index :rails_pulse_operations, :operation_type, name: 'index_rails_pulse_operations_on_operation_type'
    add_index :rails_pulse_operations, :occurred_at, name: 'index_rails_pulse_operations_on_occurred_at'

    # Performance indexes for queries page optimization
    add_index :rails_pulse_operations, [ :query_id, :occurred_at ], name: 'index_rails_pulse_operations_on_query_and_time'
    add_index :rails_pulse_operations, [ :query_id, :duration, :occurred_at ], name: 'index_rails_pulse_operations_query_performance'
    add_index :rails_pulse_operations, [ :occurred_at, :duration, :operation_type ], name: 'index_rails_pulse_operations_on_time_duration_type'
  end
end
