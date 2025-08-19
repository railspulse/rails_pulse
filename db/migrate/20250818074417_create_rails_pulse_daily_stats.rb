class CreateRailsPulseDailyStats < ActiveRecord::Migration[8.0]
  def change
    create_table :rails_pulse_daily_stats do |t|
      t.date :date, null: false, comment: "The date this stat record represents"
      t.string :entity_type, null: false, comment: "Type of entity: route, request, query"
      t.bigint :entity_id, null: true, comment: "ID of the entity (route_id, request_id, etc.)"

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
    add_index :rails_pulse_daily_stats, [ :date, :entity_type, :entity_id ],
              unique: true, name: "index_daily_stats_on_date_entity_type_entity_id"

    # Query performance indexes
    add_index :rails_pulse_daily_stats, [ :date, :entity_type ],
              name: "index_daily_stats_on_date_and_entity_type"
    add_index :rails_pulse_daily_stats, [ :entity_type, :entity_id ],
              name: "index_daily_stats_on_entity_type_and_entity_id"
  end
end
