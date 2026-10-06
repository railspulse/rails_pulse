class CreateRailsPulseCloudTables < ActiveRecord::Migration[7.0]
  def change
    unless table_exists?(:rails_pulse_cloud_installations)
      create_table :rails_pulse_cloud_installations do |t|
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

      add_index :rails_pulse_cloud_installations, :installation_id, unique: true,
        name: "index_rp_cloud_installations_on_installation_id"
    end

    unless table_exists?(:rails_pulse_cloud_batches)
      create_table :rails_pulse_cloud_batches do |t|
        t.string   :batch_id,        limit: 36, null: false, comment: "The batch's UUID, resent unchanged on every retry"
        t.binary   :payload,         limit: 16.megabytes, null: false, comment: "The batch as gzipped JSON"
        t.integer  :byte_size,       null: false, comment: "Size of the gzipped payload, for the buffer limit"
        t.integer  :item_count,      null: false
        t.integer  :attempts,        null: false, default: 0
        t.datetime :next_attempt_at, null: false, comment: "Not sent before this; set by backoff and Retry-After"
        t.text     :last_error
        t.timestamps
      end

      add_index :rails_pulse_cloud_batches, :batch_id, unique: true, name: "index_rp_cloud_batches_on_batch_id"
      add_index :rails_pulse_cloud_batches, :next_attempt_at, name: "index_rp_cloud_batches_on_next_attempt_at"
      add_index :rails_pulse_cloud_batches, :created_at, name: "index_rp_cloud_batches_on_created_at"
    end
  end
end
