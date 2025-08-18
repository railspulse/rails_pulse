# Rails Pulse Database Schema
# This file contains the complete schema for Rails Pulse tables
# Load with: rails db:schema:load:rails_pulse or db:prepare

RailsPulse::Schema = lambda do |connection|
  # Skip if tables already exist to prevent conflicts
  return if connection.table_exists?(:rails_pulse_routes)

  connection.create_table :rails_pulse_routes do |t|
    t.string :method, null: false, comment: "HTTP method (e.g., GET, POST)"
    t.string :path, null: false, comment: "Request path (e.g., /posts/index)"
    t.timestamps
  end

  connection.add_index :rails_pulse_routes, [ :method, :path ], unique: true, name: "index_rails_pulse_routes_on_method_and_path"

  connection.create_table :rails_pulse_queries do |t|
    t.string :normalized_sql, limit: 1000, null: false, comment: "Normalized SQL query string (e.g., SELECT * FROM users WHERE id = ?)"
    t.timestamps
  end

  connection.add_index :rails_pulse_queries, :normalized_sql, unique: true, name: "index_rails_pulse_queries_on_normalized_sql", length: 191

  connection.create_table :rails_pulse_requests do |t|
    t.references :route, null: false, foreign_key: { to_table: :rails_pulse_routes }, comment: "Link to the route"
    t.decimal :duration, precision: 15, scale: 6, null: false, comment: "Total request duration in milliseconds"
    t.integer :status, null: false, comment: "HTTP status code (e.g., 200, 500)"
    t.boolean :is_error, null: false, default: false, comment: "True if status >= 500"
    t.string :request_uuid, null: false, comment: "Unique identifier for the request (e.g., UUID)"
    t.string :controller_action, comment: "Controller and action handling the request (e.g., PostsController#show)"
    t.timestamp :occurred_at, null: false, comment: "When the request started"
    t.timestamps
  end

  connection.add_index :rails_pulse_requests, :occurred_at, name: "index_rails_pulse_requests_on_occurred_at"
  connection.add_index :rails_pulse_requests, :request_uuid, unique: true, name: "index_rails_pulse_requests_on_request_uuid"
  connection.add_index :rails_pulse_requests, [ :route_id, :occurred_at ], name: "index_rails_pulse_requests_on_route_id_and_occurred_at"

  connection.create_table :rails_pulse_operations do |t|
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

  connection.add_index :rails_pulse_operations, :operation_type, name: "index_rails_pulse_operations_on_operation_type"
  connection.add_index :rails_pulse_operations, :occurred_at, name: "index_rails_pulse_operations_on_occurred_at"
  connection.add_index :rails_pulse_operations, [ :query_id, :occurred_at ], name: "index_rails_pulse_operations_on_query_and_time"
  connection.add_index :rails_pulse_operations, [ :query_id, :duration, :occurred_at ], name: "index_rails_pulse_operations_query_performance"
  connection.add_index :rails_pulse_operations, [ :occurred_at, :duration, :operation_type ], name: "index_rails_pulse_operations_on_time_duration_type"

  connection.create_table :rails_pulse_daily_stats do |t|
    t.date :date, null: false, comment: "The date this stat record represents"
    t.string :entity_type, null: false, comment: "Type of entity: route, request, query"
    t.bigint :entity_id, null: false, comment: "ID of the entity (route_id, request_id, etc.)"

    # Daily aggregates
    t.integer :total_requests, null: false, default: 0, comment: "Total requests for this entity on this date"
    t.decimal :avg_duration, precision: 15, scale: 6, comment: "Average duration in milliseconds"
    t.decimal :max_duration, precision: 15, scale: 6, comment: "Maximum duration in milliseconds"
    t.integer :error_count, null: false, default: 0, comment: "Total errors for this entity on this date"
    t.decimal :p95_duration, precision: 15, scale: 6, comment: "95th percentile duration in milliseconds"

    # Hourly breakdown stored as JSON
    t.json :hourly_data, comment: "Hourly breakdowns: {\"14\": {\"requests\": 45, \"avg_duration\": 234}}"

    t.timestamps
  end

  # Unique constraint
  connection.add_index :rails_pulse_daily_stats, [ :date, :entity_type, :entity_id ],
            unique: true, name: "index_daily_stats_on_date_entity_type_entity_id"

  # Query performance indexes
  connection.add_index :rails_pulse_daily_stats, [ :date, :entity_type ],
            name: "index_daily_stats_on_date_and_entity_type"
  connection.add_index :rails_pulse_daily_stats, [ :entity_type, :entity_id ],
            name: "index_daily_stats_on_entity_type_and_entity_id"
end

if defined?(RailsPulse::ApplicationRecord)
  RailsPulse::Schema.call(RailsPulse::ApplicationRecord.connection)
end
