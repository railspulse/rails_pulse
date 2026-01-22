# frozen_string_literal: true

class OptimizeRailsPulseIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    # Remove redundant indexes that are covered by composite indexes
    # These were identified by PgHero as being redundant

    # Operations table - remove 3 redundant indexes
    if index_exists?(:rails_pulse_operations, :created_at, name: "idx_operations_created_at")
      remove_index :rails_pulse_operations, :created_at, name: :idx_operations_created_at, **index_options
    end

    if index_exists?(:rails_pulse_operations, :occurred_at, name: "index_rails_pulse_operations_on_occurred_at")
      remove_index :rails_pulse_operations, :occurred_at, name: :index_rails_pulse_operations_on_occurred_at, **index_options
    end

    if index_exists?(:rails_pulse_operations, :query_id, name: "index_rails_pulse_operations_on_query_id")
      remove_index :rails_pulse_operations, :query_id, name: :index_rails_pulse_operations_on_query_id, **index_options
    end

    # Requests table - remove 2 redundant indexes
    if index_exists?(:rails_pulse_requests, :created_at, name: "idx_requests_created_at")
      remove_index :rails_pulse_requests, :created_at, name: :idx_requests_created_at, **index_options
    end

    if index_exists?(:rails_pulse_requests, :route_id, name: "index_rails_pulse_requests_on_route_id")
      remove_index :rails_pulse_requests, :route_id, name: :index_rails_pulse_requests_on_route_id, **index_options
    end

    # Summaries table - remove 1 redundant index
    if index_exists?(:rails_pulse_summaries, [ :summarizable_type, :summarizable_id ], name: "index_rails_pulse_summaries_on_summarizable")
      remove_index :rails_pulse_summaries, [ :summarizable_type, :summarizable_id ], name: :index_rails_pulse_summaries_on_summarizable, **index_options
    end

    # Add missing indexes for better query performance
    unless index_exists?(:rails_pulse_summaries, :summarizable_id, name: "index_rails_pulse_summaries_on_summarizable_id")
      add_index :rails_pulse_summaries, :summarizable_id, name: :index_rails_pulse_summaries_on_summarizable_id, **index_options
    end

    unless index_exists?(:rails_pulse_routes, :path, name: "index_rails_pulse_routes_on_path")
      add_index :rails_pulse_routes, :path, name: :index_rails_pulse_routes_on_path, **index_options
    end

    unless index_exists?(:rails_pulse_summaries, :period_start, name: "index_rails_pulse_summaries_on_period_start")
      add_index :rails_pulse_summaries, :period_start, name: :index_rails_pulse_summaries_on_period_start, **index_options
    end
  end

  def down
    # Restore the removed indexes
    unless index_exists?(:rails_pulse_operations, :created_at, name: "idx_operations_created_at")
      add_index :rails_pulse_operations, :created_at, name: :idx_operations_created_at, **index_options
    end

    unless index_exists?(:rails_pulse_operations, :occurred_at, name: "index_rails_pulse_operations_on_occurred_at")
      add_index :rails_pulse_operations, :occurred_at, name: :index_rails_pulse_operations_on_occurred_at, **index_options
    end

    unless index_exists?(:rails_pulse_operations, :query_id, name: "index_rails_pulse_operations_on_query_id")
      add_index :rails_pulse_operations, :query_id, name: :index_rails_pulse_operations_on_query_id, **index_options
    end

    unless index_exists?(:rails_pulse_requests, :created_at, name: "idx_requests_created_at")
      add_index :rails_pulse_requests, :created_at, name: :idx_requests_created_at, **index_options
    end

    unless index_exists?(:rails_pulse_requests, :route_id, name: "index_rails_pulse_requests_on_route_id")
      add_index :rails_pulse_requests, :route_id, name: :index_rails_pulse_requests_on_route_id, **index_options
    end

    unless index_exists?(:rails_pulse_summaries, [ :summarizable_type, :summarizable_id ], name: "index_rails_pulse_summaries_on_summarizable")
      add_index :rails_pulse_summaries, [ :summarizable_type, :summarizable_id ], name: :index_rails_pulse_summaries_on_summarizable, **index_options
    end

    # Remove the added indexes
    if index_exists?(:rails_pulse_summaries, :summarizable_id, name: "index_rails_pulse_summaries_on_summarizable_id")
      remove_index :rails_pulse_summaries, :summarizable_id, name: :index_rails_pulse_summaries_on_summarizable_id, **index_options
    end

    if index_exists?(:rails_pulse_routes, :path, name: "index_rails_pulse_routes_on_path")
      remove_index :rails_pulse_routes, :path, name: :index_rails_pulse_routes_on_path, **index_options
    end

    if index_exists?(:rails_pulse_summaries, :period_start, name: "index_rails_pulse_summaries_on_period_start")
      remove_index :rails_pulse_summaries, :period_start, name: :index_rails_pulse_summaries_on_period_start, **index_options
    end
  end

  private

  def index_options
    # Use concurrent indexing for PostgreSQL, standard for others
    if postgresql?
      { algorithm: :concurrently }
    else
      {}
    end
  end

  def postgresql?
    connection.adapter_name.downcase.include?("postgres")
  end
end
