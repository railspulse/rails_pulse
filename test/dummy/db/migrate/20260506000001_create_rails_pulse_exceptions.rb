class CreateRailsPulseExceptions < ActiveRecord::Migration[7.0]
  def up
    unless table_exists?(:rails_pulse_exception_groups)
      create_table :rails_pulse_exception_groups do |t|
        t.string   :fingerprint,      null: false, comment: "SHA256 of exception_class + first app-code frame"
        t.string   :exception_class,  null: false, comment: "e.g. ActiveRecord::RecordNotFound"
        t.text     :message,                       comment: "Message from the most recent occurrence"
        t.datetime :first_seen_at,    null: false
        t.datetime :last_seen_at,     null: false
        t.integer  :occurrence_count, null: false, default: 0
        t.timestamps
      end

      add_index :rails_pulse_exception_groups, :fingerprint,     unique: true, name: "index_rp_exception_groups_on_fingerprint"
      add_index :rails_pulse_exception_groups, :last_seen_at,                  name: "index_rp_exception_groups_on_last_seen_at"
      add_index :rails_pulse_exception_groups, :exception_class,               name: "index_rp_exception_groups_on_class"
    end

    unless table_exists?(:rails_pulse_exception_occurrences)
      create_table :rails_pulse_exception_occurrences do |t|
        t.references :exception_group, null: false,
                     foreign_key: { to_table: :rails_pulse_exception_groups },
                     comment: "FK to the group this occurrence belongs to"
        t.string   :exception_class, null: false
        t.text     :message
        t.text     :backtrace,       comment: "JSON array of {file, line, method} frames"
        t.string   :request_url,     comment: "Nullable — web requests only"
        t.string   :request_method,  comment: "GET, POST, etc."
        t.string   :environment,     comment: "production, staging, etc."
        t.string   :deploy_sha,      comment: "Captured now even though Pro uses it — cannot backfill later"
        t.datetime :occurred_at,     null: false
        t.timestamps
      end

      add_index :rails_pulse_exception_occurrences, :occurred_at,        name: "index_rp_exception_occurrences_on_occurred_at"
      add_index :rails_pulse_exception_occurrences, :exception_group_id, name: "index_rp_exception_occurrences_on_group_id"
    end
  end

  def down
    drop_table :rails_pulse_exception_occurrences if table_exists?(:rails_pulse_exception_occurrences)
    drop_table :rails_pulse_exception_groups if table_exists?(:rails_pulse_exception_groups)
  end
end
