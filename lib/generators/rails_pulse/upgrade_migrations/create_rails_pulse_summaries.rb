class CreateRailsPulseSummaries < ActiveRecord::Migration[<%= ActiveRecord::Migration.current_version %>]
  def change
    return if table_exists?(:rails_pulse_summaries)

    create_table :rails_pulse_summaries do |t|
      # Time fields
      t.datetime :period_start, null: false, comment: "Start of the aggregation period"
      t.datetime :period_end, null: false, comment: "End of the aggregation period"
      t.string :period_type, null: false, comment: "Aggregation period type: hour, day, week, month"

      # Polymorphic association to handle both routes and queries
      t.references :summarizable, polymorphic: true, null: false, index: true, comment: "Link to Route or Query"

      # Universal metrics
      t.integer :count, default: 0, null: false, comment: "Total number of requests/operations"
      t.float :avg_duration, comment: "Average duration in milliseconds"
      t.float :min_duration, comment: "Minimum duration in milliseconds"
      t.float :max_duration, comment: "Maximum duration in milliseconds"
      t.float :p50_duration, comment: "50th percentile duration"
      t.float :p95_duration, comment: "95th percentile duration"
      t.float :p99_duration, comment: "99th percentile duration"
      t.float :total_duration, comment: "Total duration in milliseconds"
      t.float :stddev_duration, comment: "Standard deviation of duration"

      # Request/Route specific metrics
      t.integer :error_count, default: 0, comment: "Number of error responses (5xx)"
      t.integer :success_count, default: 0, comment: "Number of successful responses"
      t.integer :status_2xx, default: 0, comment: "Number of 2xx responses"
      t.integer :status_3xx, default: 0, comment: "Number of 3xx responses"
      t.integer :status_4xx, default: 0, comment: "Number of 4xx responses"
      t.integer :status_5xx, default: 0, comment: "Number of 5xx responses"

      t.timestamps
    end

    # Unique constraint and indexes for summaries
    add_index :rails_pulse_summaries, [ :summarizable_type, :summarizable_id, :period_type, :period_start ],
              unique: true,
              name: "idx_pulse_summaries_unique"
    add_index :rails_pulse_summaries, [ :period_type, :period_start ], name: "index_rails_pulse_summaries_on_period"
    add_index :rails_pulse_summaries, :created_at, name: "index_rails_pulse_summaries_on_created_at"

    # Additional aggregation indexes
    unless index_exists?(:rails_pulse_requests, [ :created_at, :route_id ], name: "idx_requests_for_aggregation")
      add_index :rails_pulse_requests, [ :created_at, :route_id ], name: "idx_requests_for_aggregation"
    end

    unless index_exists?(:rails_pulse_requests, :created_at, name: "idx_requests_created_at")
      add_index :rails_pulse_requests, :created_at, name: "idx_requests_created_at"
    end

    unless index_exists?(:rails_pulse_operations, [ :created_at, :query_id ], name: "idx_operations_for_aggregation")
      add_index :rails_pulse_operations, [ :created_at, :query_id ], name: "idx_operations_for_aggregation"
    end

    unless index_exists?(:rails_pulse_operations, :created_at, name: "idx_operations_created_at")
      add_index :rails_pulse_operations, :created_at, name: "idx_operations_created_at"
    end
  end
end
