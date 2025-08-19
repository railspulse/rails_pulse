class AddIndexesToRailsPulseOperationsForQueries < ActiveRecord::Migration[8.0]
  def change
    # Composite index for query aggregation queries
    # Covers: query_id (for JOIN), occurred_at (for time filtering), duration (for filtering/aggregation)
    add_index :rails_pulse_operations, [:query_id, :occurred_at, :duration],
              name: 'index_operations_on_query_time_duration'

    # Index for time-based filtering (when filtering operations first)
    # Covers: occurred_at (for time range), query_id (for JOIN back to queries)
    add_index :rails_pulse_operations, [:occurred_at, :query_id],
              name: 'index_operations_on_time_query'

    # Additional index for duration filtering
    add_index :rails_pulse_operations, [:duration, :occurred_at],
              name: 'index_operations_on_duration_time'
  end
end
