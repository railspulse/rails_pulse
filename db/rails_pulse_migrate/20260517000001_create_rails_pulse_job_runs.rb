# Add rails_pulse_jobs and rails_pulse_job_runs tables for background job monitoring
class CreateRailsPulseJobRuns < ActiveRecord::Migration[7.0]
  def up
    unless table_exists?(:rails_pulse_jobs)
      create_table :rails_pulse_jobs do |t|
        t.string  :name,            null: false, comment: "Job class name"
        t.string  :queue_name,                   comment: "Default queue"
        t.text    :description,                  comment: "Optional description"
        t.integer :runs_count,      null: false, default: 0, comment: "Cache of total runs"
        t.integer :failures_count,  null: false, default: 0, comment: "Cache of failed runs"
        t.integer :retries_count,   null: false, default: 0, comment: "Cache of retried runs"
        t.decimal :avg_duration,    precision: 15, scale: 6, comment: "Average duration in milliseconds"
        t.decimal :p95_duration,    precision: 15, scale: 6, comment: "95th percentile duration in milliseconds"
        t.decimal :p99_duration,    precision: 15, scale: 6, comment: "99th percentile duration in milliseconds"
        t.text    :tags,                         comment: "JSON array of tags"
        t.timestamps
      end

      add_index :rails_pulse_jobs, :name,        unique: true, name: "index_rails_pulse_jobs_on_name"
      add_index :rails_pulse_jobs, :queue_name,               name: "index_rails_pulse_jobs_on_queue"
      add_index :rails_pulse_jobs, :runs_count,               name: "index_rails_pulse_jobs_on_runs_count"
    end

    unless table_exists?(:rails_pulse_job_runs)
      create_table :rails_pulse_job_runs do |t|
        t.references :job,          null: false, foreign_key: { to_table: :rails_pulse_jobs }, comment: "Link to job definition"
        t.string     :run_id,       null: false, comment: "Adapter specific run id"
        t.decimal    :duration,     precision: 15, scale: 6, comment: "Execution duration in milliseconds"
        t.string     :status,       null: false, comment: "Execution status"
        t.string     :error_class,               comment: "Error class name"
        t.text       :error_message,             comment: "Error message"
        t.integer    :attempts,     null: false, default: 0, comment: "Retry attempts"
        t.timestamp  :occurred_at,  null: false, comment: "When the job started"
        t.timestamp  :enqueued_at,               comment: "When the job was enqueued"
        t.text       :arguments,                 comment: "Serialized arguments"
        t.string     :adapter,                   comment: "Queue adapter"
        t.text       :tags,                      comment: "Execution tags"
        t.timestamps
      end

      add_index :rails_pulse_job_runs, :run_id, unique: true,
        name: "index_rails_pulse_job_runs_on_run_id"
      add_index :rails_pulse_job_runs, [ :job_id, :occurred_at ],
        name: "index_rails_pulse_job_runs_on_job_and_occurred"
      add_index :rails_pulse_job_runs, :occurred_at,
        name: "index_rails_pulse_job_runs_on_occurred_at"
      add_index :rails_pulse_job_runs, :status,
        name: "index_rails_pulse_job_runs_on_status"
      add_index :rails_pulse_job_runs, [ :job_id, :status ],
        name: "index_rails_pulse_job_runs_on_job_and_status"
    end
  end

  def down
    drop_table :rails_pulse_job_runs if table_exists?(:rails_pulse_job_runs)
    drop_table :rails_pulse_jobs if table_exists?(:rails_pulse_jobs)
  end
end
