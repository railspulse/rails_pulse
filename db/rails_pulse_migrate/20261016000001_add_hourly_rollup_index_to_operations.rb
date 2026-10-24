class AddHourlyRollupIndexToOperations < ActiveRecord::Migration[7.2]
  def change
    return unless table_exists?(:rails_pulse_operations)

    unless index_exists?(:rails_pulse_operations, [ :occurred_at, :query_id, :duration ], name: "index_rails_pulse_operations_hourly_rollup")
      # Covers the hourly summary's one read of the table (query_id and
      # duration for a window of occurred_at) so it never touches the heap,
      # whose rows carry unbounded text columns.
      add_index :rails_pulse_operations, [ :occurred_at, :query_id, :duration ], name: "index_rails_pulse_operations_hourly_rollup"
    end
  end
end
