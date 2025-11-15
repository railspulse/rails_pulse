# frozen_string_literal: true

class InstallRailsPulseTables < ActiveRecord::Migration[7.2]
  def up
    # Check if Rails Pulse is already installed
    if rails_pulse_installed?
      say "Rails Pulse tables already exist. Skipping installation.", :yellow
      return
    end

    schema_file = File.join(Rails.root.to_s, "db/rails_pulse_schema.rb")

    if File.exist?(schema_file)
      say "Loading Rails Pulse schema from db/rails_pulse_schema.rb"
      load schema_file
      RailsPulse::Schema.call(connection)
      say "Rails Pulse tables created successfully"
    else
      raise "Rails Pulse schema file not found at db/rails_pulse_schema.rb"
    end
  end

  def down
    # Rollback: drop all Rails Pulse tables in reverse dependency order
    say "Dropping Rails Pulse tables..."
    drop_table :rails_pulse_operations if table_exists?(:rails_pulse_operations)
    drop_table :rails_pulse_job_runs if table_exists?(:rails_pulse_job_runs)
    drop_table :rails_pulse_jobs if table_exists?(:rails_pulse_jobs)
    drop_table :rails_pulse_summaries if table_exists?(:rails_pulse_summaries)
    drop_table :rails_pulse_requests if table_exists?(:rails_pulse_requests)
    drop_table :rails_pulse_routes if table_exists?(:rails_pulse_routes)
    drop_table :rails_pulse_queries if table_exists?(:rails_pulse_queries)
    say "Rails Pulse tables dropped successfully"
  end

  private

  def rails_pulse_installed?
    table_exists?(:rails_pulse_routes) && table_exists?(:rails_pulse_requests)
  end
end
