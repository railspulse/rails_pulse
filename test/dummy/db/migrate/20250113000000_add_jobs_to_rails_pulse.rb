# Add background job tracking to Rails Pulse
class AddJobsToRailsPulse < ActiveRecord::Migration[7.0]
  def up
    # Create jobs table for storing job definitions
    unless table_exists?(:rails_pulse_jobs)
      create_table :rails_pulse_jobs do |t|
        t.string :name, null: false, comment: "Job class name"
        t.string :queue_name, comment: "Default queue"
        t.text :description, comment: "Optional description"
        t.integer :runs_count, null: false, default: 0, comment: "Cache of total runs"
        t.integer :failures_count, null: false, default: 0, comment: "Cache of failed runs"
        t.integer :retries_count, null: false, default: 0, comment: "Cache of retried runs"
        t.decimal :avg_duration, precision: 15, scale: 6, comment: "Average duration in milliseconds"
        t.text :tags, comment: "JSON array of tags"
        t.timestamps
      end

      add_index :rails_pulse_jobs, :name, unique: true, name: "index_rails_pulse_jobs_on_name"
      add_index :rails_pulse_jobs, :queue_name, name: "index_rails_pulse_jobs_on_queue"
      add_index :rails_pulse_jobs, :runs_count, name: "index_rails_pulse_jobs_on_runs_count"
    end

    # Create job_runs table for individual job executions
    unless table_exists?(:rails_pulse_job_runs)
      create_table :rails_pulse_job_runs do |t|
        t.references :job, null: false, foreign_key: { to_table: :rails_pulse_jobs }, comment: "Link to job definition"
        t.string :run_id, null: false, comment: "Adapter specific run id"
        t.decimal :duration, precision: 15, scale: 6, comment: "Execution duration in milliseconds"
        t.string :status, null: false, comment: "Execution status"
        t.string :error_class, comment: "Error class name"
        t.text :error_message, comment: "Error message"
        t.integer :attempts, null: false, default: 0, comment: "Retry attempts"
        t.timestamp :occurred_at, null: false, comment: "When the job started"
        t.timestamp :enqueued_at, comment: "When the job was enqueued"
        t.text :arguments, comment: "Serialized arguments"
        t.string :adapter, comment: "Queue adapter"
        t.text :tags, comment: "Execution tags"
        t.timestamps
      end

      add_index :rails_pulse_job_runs, :run_id, unique: true, name: "index_rails_pulse_job_runs_on_run_id"
      add_index :rails_pulse_job_runs, [ :job_id, :occurred_at ], name: "index_rails_pulse_job_runs_on_job_and_occurred"
      add_index :rails_pulse_job_runs, :occurred_at, name: "index_rails_pulse_job_runs_on_occurred_at"
      add_index :rails_pulse_job_runs, :status, name: "index_rails_pulse_job_runs_on_status"
      add_index :rails_pulse_job_runs, [ :job_id, :status ], name: "index_rails_pulse_job_runs_on_job_and_status"
    end

    # Add job_run_id to operations table if it doesn't exist
    if table_exists?(:rails_pulse_operations) && !column_exists?(:rails_pulse_operations, :job_run_id)
      # Make request_id nullable to allow job operations
      change_column_null :rails_pulse_operations, :request_id, true

      # Add job_run_id reference
      add_reference :rails_pulse_operations, :job_run,
        null: true,
        foreign_key: { to_table: :rails_pulse_job_runs },
        comment: "Link to a background job execution"

      # Add check constraint for PostgreSQL and MySQL to ensure either request_id or job_run_id is present
      adapter = connection.adapter_name.downcase
      if adapter.include?("postgres") || adapter.include?("mysql")
        execute <<-SQL
          ALTER TABLE rails_pulse_operations
          ADD CONSTRAINT rails_pulse_operations_request_or_job_run
          CHECK (request_id IS NOT NULL OR job_run_id IS NOT NULL)
        SQL
      end
    end
  end

  def down
    # Remove check constraint first
    adapter = connection.adapter_name.downcase
    if adapter.include?("postgres") || adapter.include?("mysql")
      execute <<-SQL
        ALTER TABLE rails_pulse_operations
        DROP CONSTRAINT IF EXISTS rails_pulse_operations_request_or_job_run
      SQL
    end

    # Remove job_run_id from operations
    if column_exists?(:rails_pulse_operations, :job_run_id)
      remove_reference :rails_pulse_operations, :job_run, foreign_key: { to_table: :rails_pulse_job_runs }
    end

    # Make request_id non-nullable again
    if column_exists?(:rails_pulse_operations, :request_id)
      change_column_null :rails_pulse_operations, :request_id, false
    end

    # Drop job tables
    drop_table :rails_pulse_job_runs if table_exists?(:rails_pulse_job_runs)
    drop_table :rails_pulse_jobs if table_exists?(:rails_pulse_jobs)
  end
end
