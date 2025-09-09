class CreateRailsPulseSummaries < ActiveRecord::Migration[7.1]
  def change
    create_table :rails_pulse_summaries do |t|
      # Time fields
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.string :period_type, null: false # 'hour', 'day', 'week', 'month'

      # Polymorphic association to handle both routes and queries
      t.references :summarizable, polymorphic: true, null: false, index: true
      # This creates summarizable_type (e.g., 'RailsPulse::Route', 'RailsPulse::Query')
      # and summarizable_id (route_id or query_id)

      # Universal metrics
      t.integer :count, default: 0, null: false
      t.float :avg_duration
      t.float :min_duration
      t.float :max_duration
      t.float :p50_duration
      t.float :p95_duration
      t.float :p99_duration
      t.float :total_duration
      t.float :stddev_duration

      # Request/Route specific metrics
      t.integer :error_count, default: 0
      t.integer :success_count, default: 0
      t.integer :status_2xx, default: 0
      t.integer :status_3xx, default: 0
      t.integer :status_4xx, default: 0
      t.integer :status_5xx, default: 0

      t.timestamps

      # Unique constraint and indexes
      t.index [ :summarizable_type, :summarizable_id, :period_type, :period_start ],
              unique: true,
              name: 'idx_pulse_summaries_unique'
      t.index [ :period_type, :period_start ]
      t.index :created_at
    end

    # Add indexes to existing tables for efficient aggregation
    add_index :rails_pulse_requests, [ :created_at, :route_id ],
              name: 'idx_requests_for_aggregation'
    add_index :rails_pulse_requests, :created_at,
              name: 'idx_requests_created_at'

    add_index :rails_pulse_operations, [ :created_at, :query_id ],
              name: 'idx_operations_for_aggregation'
    add_index :rails_pulse_operations, :created_at,
              name: 'idx_operations_created_at'
  end
end
