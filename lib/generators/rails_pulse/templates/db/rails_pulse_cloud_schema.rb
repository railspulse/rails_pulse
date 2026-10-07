# Rails Pulse Cloud Database Schema
# The tables Rails Pulse Cloud's sync needs, kept apart from
# db/rails_pulse_schema.rb so an install that does not use Cloud never has
# them. Installed by `rails generate rails_pulse:install_cloud`; loaded by its
# migration, and by db:prepare on a separate Rails Pulse database.

RailsPulse::CloudSchema = lambda do |connection|
  required_tables = [ :rails_pulse_cloud_installations, :rails_pulse_cloud_batches ]

  missing_tables = required_tables.reject { |table| connection.table_exists?(table) }
  if missing_tables.empty?
    puts "[RailsPulse::CloudSchema] All Rails Pulse Cloud tables already exist. Skipping schema load."
    return
  end

  puts "[RailsPulse::CloudSchema] Creating missing tables: #{missing_tables.join(', ')}"

  unless connection.table_exists?(:rails_pulse_cloud_installations)
    connection.create_table :rails_pulse_cloud_installations do |t|
      t.string   :installation_id, limit: 36, null: false, comment: "UUID naming this Rails Pulse database to Rails Pulse Cloud, generated once"
      t.datetime :last_hour_sent_at,                    comment: "Start of the newest hour whose summaries were queued for Cloud"
      t.datetime :exception_groups_sent_through,        comment: "Exception groups updated before this were queued for Cloud"
      t.datetime :deployments_sent_through,             comment: "Deployments updated before this were queued for Cloud"
      t.datetime :last_success_at,                      comment: "When Cloud last accepted a batch or health update"
      t.datetime :last_health_at,                       comment: "When the last health update was sent"
      t.text     :last_error,                           comment: "The most recent failure, for rails_pulse:status"
      t.datetime :last_error_at
      t.datetime :paused_until,                         comment: "No sending before this, after Cloud refused the key, plan, application or contract"
      t.text     :pause_reason,                         comment: "Cloud's message for the pause"
      t.string   :contract_deprecated_on,               comment: "Date from Cloud's Rails-Pulse-Contract-Deprecated header"
      t.timestamps
    end

    connection.add_index :rails_pulse_cloud_installations, :installation_id, unique: true,
      name: "index_rp_cloud_installations_on_installation_id"
  end

  unless connection.table_exists?(:rails_pulse_cloud_batches)
    connection.create_table :rails_pulse_cloud_batches do |t|
      t.string   :batch_id,        limit: 36, null: false, comment: "The batch's UUID, resent unchanged on every retry"
      t.binary   :payload,         limit: 16.megabytes, null: false, comment: "The batch as gzipped JSON"
      t.integer  :byte_size,       null: false, comment: "Size of the gzipped payload, for the buffer limit"
      t.integer  :item_count,      null: false
      t.integer  :attempts,        null: false, default: 0
      t.datetime :next_attempt_at, null: false, comment: "Not sent before this; set by backoff and Retry-After"
      t.text     :last_error
      t.timestamps
    end

    connection.add_index :rails_pulse_cloud_batches, :batch_id, unique: true, name: "index_rp_cloud_batches_on_batch_id"
    connection.add_index :rails_pulse_cloud_batches, :next_attempt_at, name: "index_rp_cloud_batches_on_next_attempt_at"
    connection.add_index :rails_pulse_cloud_batches, :created_at, name: "index_rp_cloud_batches_on_created_at"
  end
end unless defined?(RailsPulse::CloudSchema)

if defined?(RailsPulse::ApplicationRecord)
  RailsPulse::CloudSchema.call(RailsPulse::ApplicationRecord.connection)
end
