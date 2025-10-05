# Generated from Rails Pulse schema - simplified for testing
class InstallRailsPulseTables < ActiveRecord::Migration[7.2]
  def change
    # Load the Rails Pulse schema file directly
    schema_file = File.join(File.dirname(__FILE__), "..", "rails_pulse_schema.rb")

    if File.exist?(schema_file)
      say "Loading Rails Pulse schema..."
      load schema_file
      RailsPulse::Schema.call(connection)
      say "Rails Pulse tables created successfully"
    else
      # Fallback: create tables directly
      say "Schema file not found, creating tables directly..."

      create_table :rails_pulse_routes do |t|
        t.string :method, null: false
        t.string :path, null: false
        t.timestamps
      end
      add_index :rails_pulse_routes, [ :method, :path ], unique: true

      create_table :rails_pulse_queries do |t|
        t.string :normalized_sql, limit: 1000, null: false
        t.datetime :analyzed_at
        t.text :explain_plan
        t.text :issues
        t.text :metadata
        t.text :query_stats
        t.text :backtrace_analysis
        t.text :index_recommendations
        t.text :n_plus_one_analysis
        t.text :suggestions
        t.timestamps
      end
      # Limit index length for MySQL compatibility (3072 byte limit)
      add_index :rails_pulse_queries, :normalized_sql, unique: true, length: 191

      create_table :rails_pulse_requests do |t|
        t.references :route, null: false, foreign_key: { to_table: :rails_pulse_routes }
        t.decimal :duration, precision: 15, scale: 6, null: false
        t.integer :status, null: false
        t.boolean :is_error, null: false, default: false
        t.string :request_uuid, null: false
        t.string :controller_action
        t.timestamp :occurred_at, null: false
        t.timestamps
      end
      add_index :rails_pulse_requests, :occurred_at
      add_index :rails_pulse_requests, :request_uuid, unique: true

      create_table :rails_pulse_operations do |t|
        t.references :request, null: false, foreign_key: { to_table: :rails_pulse_requests }
        t.references :query, foreign_key: { to_table: :rails_pulse_queries }, index: true
        t.string :operation_type, null: false
        t.string :label, null: false
        t.decimal :duration, precision: 15, scale: 6, null: false
        t.string :codebase_location
        t.float :start_time, null: false, default: 0.0
        t.timestamp :occurred_at, null: false
        t.timestamps
      end
      add_index :rails_pulse_operations, :operation_type
      add_index :rails_pulse_operations, :occurred_at

      create_table :rails_pulse_summaries do |t|
        t.datetime :period_start, null: false
        t.datetime :period_end, null: false
        t.string :period_type, null: false
        t.references :summarizable, polymorphic: true, null: false, index: true
        t.integer :count, default: 0, null: false
        t.float :avg_duration
        t.float :min_duration
        t.float :max_duration
        t.float :p50_duration
        t.float :p95_duration
        t.float :p99_duration
        t.float :total_duration
        t.float :stddev_duration
        t.integer :error_count, default: 0
        t.integer :success_count, default: 0
        t.integer :status_2xx, default: 0
        t.integer :status_3xx, default: 0
        t.integer :status_4xx, default: 0
        t.integer :status_5xx, default: 0
        t.timestamps
      end
      add_index :rails_pulse_summaries, [ :summarizable_type, :summarizable_id, :period_type, :period_start ],
                unique: true, name: "idx_pulse_summaries_unique"
    end
  end
end
