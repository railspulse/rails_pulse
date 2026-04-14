module GeneratorTestHelpers
  def schema_content
    File.read(File.expand_path("../../lib/generators/rails_pulse/templates/db/rails_pulse_schema.rb", __dir__))
  end

  def single_database_yml
    <<~YAML
      development:
        adapter: sqlite3
        database: db/development.sqlite3
    YAML
  end

  def single_database_yml_with_aliases
    <<~YAML
      default: &default
        adapter: sqlite3
        pool: 5

      development:
        <<: *default
        database: db/development.sqlite3

      test:
        <<: *default
        database: db/test.sqlite3
    YAML
  end

  def separate_database_yml_with_aliases
    <<~YAML
      default: &default
        adapter: sqlite3
        pool: 5

      development:
        <<: *default
        database: db/development.sqlite3

      test:
        <<: *default
        rails_pulse:
          adapter: sqlite3
          database: db/test_rails_pulse.sqlite3
          migrations_paths: db/rails_pulse_migrate
    YAML
  end

  def separate_database_yml
    <<~YAML
      development:
        adapter: sqlite3
        database: db/development.sqlite3

      test:
        rails_pulse:
          adapter: sqlite3
          database: db/test_rails_pulse.sqlite3
          migrations_paths: db/rails_pulse_migrate
    YAML
  end

  def migration_content(name, class_name = nil)
    class_name ||= name.camelize
    <<~RUBY
      class #{class_name} < ActiveRecord::Migration[7.0]
        def change
          # Migration content for #{name}
        end
      end
    RUBY
  end

  def create_gem_migration(name, timestamp = "20251019000000")
    gem_path = gem_migrations_path
    FileUtils.mkdir_p(gem_path)
    filename = "#{timestamp}_#{name}.rb"
    File.write(File.join(gem_path, filename), migration_content(name))
    filename
  end

  def gem_migrations_path
    # Use a test-specific gem migrations directory to avoid parallel test interference
    # This is where the test will simulate the gem's migrations directory
    File.join(destination_root, "gem_migrations")
  end

  def setup_test_app_with_schema
    FileUtils.mkdir_p(File.join(destination_root, "db"))
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "db/rails_pulse_schema.rb"), schema_content)
  end

  def assert_migration(migration_path, &block)
    # Extract directory and filename from the path
    dir = File.dirname(migration_path)
    filename = File.basename(migration_path)

    # Find the migration file (may have timestamp prefix)
    full_dir = File.join(destination_root, dir)
    pattern = File.join(full_dir, "*_#{filename}")

    matching_files = Dir.glob(pattern)

    assert_predicate matching_files, :any?, "Expected migration matching #{migration_path} to exist, but does not"

    # Read and verify the content of the first matching file
    if block_given?
      content = File.read(matching_files.first)
      block.call(content)
    end
  end

  def assert_no_migration(migration_path)
    assert_no_file migration_path
  end

  # Complete schema columns for all Rails Pulse tables
  def complete_schema_columns
    {
      rails_pulse_routes: %w[id method path tags created_at updated_at],
      rails_pulse_queries: %w[id hashed_sql normalized_sql analyzed_at explain_plan issues metadata
                              query_stats backtrace_analysis index_recommendations n_plus_one_analysis
                              suggestions tags created_at updated_at],
      rails_pulse_requests: %w[id route_id duration status is_error request_uuid controller_action
                                occurred_at tags created_at updated_at],
      rails_pulse_jobs: %w[id name queue_name description runs_count failures_count retries_count
                           avg_duration tags created_at updated_at],
      rails_pulse_job_runs: %w[id job_id run_id duration status error_class error_message attempts
                                occurred_at enqueued_at arguments adapter tags created_at updated_at],
      rails_pulse_operations: %w[id request_id job_run_id query_id operation_type label duration
                                  codebase_location start_time occurred_at created_at updated_at],
      rails_pulse_summaries: %w[id period_start period_end period_type summarizable_type summarizable_id
                                count avg_duration min_duration max_duration p50_duration p95_duration
                                p99_duration total_duration stddev_duration error_count success_count
                                status_2xx status_3xx status_4xx status_5xx created_at updated_at]
    }
  end

  # Schema columns missing the 'tags' column (for testing missing column detection)
  def schema_without_tags
    {
      rails_pulse_routes: %w[id method path created_at updated_at],
      rails_pulse_queries: %w[id hashed_sql normalized_sql analyzed_at explain_plan issues metadata
                              query_stats backtrace_analysis index_recommendations n_plus_one_analysis
                              suggestions created_at updated_at],
      rails_pulse_requests: %w[id route_id duration status is_error request_uuid controller_action
                                occurred_at created_at updated_at],
      rails_pulse_jobs: %w[id name queue_name description runs_count failures_count retries_count
                           avg_duration created_at updated_at],
      rails_pulse_job_runs: %w[id job_id run_id duration status error_class error_message attempts
                                occurred_at enqueued_at arguments adapter created_at updated_at],
      rails_pulse_operations: %w[id request_id job_run_id query_id operation_type label duration
                                  codebase_location start_time occurred_at created_at updated_at],
      rails_pulse_summaries: %w[id period_start period_end period_type summarizable_type summarizable_id
                                count avg_duration min_duration max_duration p50_duration p95_duration
                                p99_duration total_duration stddev_duration error_count success_count
                                status_2xx status_3xx status_4xx status_5xx created_at updated_at]
    }
  end
end
