require "test_helper"

# Regression tests for upgrade migrations.
# Each test starts from a historical schema snapshot, runs all current incremental
# migrations in order, then verifies the expected columns and tables exist and that
# records can be inserted into the affected tables.
#
# These tests use DDL directly and cannot be wrapped in transactions, so they
# manage their own schema lifecycle: setup loads a baseline, teardown restores
# the current schema.
class UpgradeMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  parallelize(workers: 1)

  # Skip fixture loading — tables are in a historical state during these tests
  def setup_fixtures(*); end
  def teardown_fixtures(*); end

  MIGRATE_DIR = File.expand_path("../../db/rails_pulse_migrate", __dir__)

  MIGRATION_CLASSES = %w[
    AddDiagnosticFields
    AddP95P99DurationToRailsPulseJobs
    ExpandNormalizedQueryColumn
    CreateRailsPulseDeployments
    AddActualQueryToOperations
    CreateRailsPulseJobRuns
  ].freeze

  def setup
    @conn = ActiveRecord::Base.connection
    restore_current_schema
  end

  def teardown
    restore_current_schema
  end

  # Structure Tests

  test "upgrade from v0.2.7 adds diagnostic columns to operations and requests" do
    load_baseline(RailsPulse::TestSchemas::V027)
    run_all_migrations

    assert @conn.column_exists?(:rails_pulse_operations, :row_count), "row_count missing on operations"
    assert @conn.column_exists?(:rails_pulse_operations, :cache_hit), "cache_hit missing on operations"
    assert @conn.column_exists?(:rails_pulse_operations, :repeated_query_group), "repeated_query_group missing on operations"
    assert @conn.column_exists?(:rails_pulse_operations, :repetition_count), "repetition_count missing on operations"
    assert @conn.column_exists?(:rails_pulse_requests, :response_size_bytes), "response_size_bytes missing on requests"
  end

  test "upgrade from v0.2.7 adds p95 and p99 duration to jobs" do
    load_baseline(RailsPulse::TestSchemas::V027)
    run_all_migrations

    assert @conn.column_exists?(:rails_pulse_jobs, :p95_duration), "p95_duration missing on jobs"
    assert @conn.column_exists?(:rails_pulse_jobs, :p99_duration), "p99_duration missing on jobs"
  end

  test "upgrade from v0.2.7 creates deployments table" do
    load_baseline(RailsPulse::TestSchemas::V027)
    run_all_migrations

    assert @conn.table_exists?(:rails_pulse_deployments), "deployments table missing"
    assert @conn.column_exists?(:rails_pulse_deployments, :revision), "revision missing on deployments"
    assert @conn.column_exists?(:rails_pulse_deployments, :started_at), "started_at missing on deployments"
  end

  test "upgrade from v0.2.7 adds actual_sql to operations" do
    load_baseline(RailsPulse::TestSchemas::V027)
    run_all_migrations

    assert @conn.column_exists?(:rails_pulse_operations, :actual_sql), "actual_sql missing on operations"
  end

  test "upgrade from v0.2.7 ensures job_runs table exists" do
    load_baseline(RailsPulse::TestSchemas::V027)
    run_all_migrations

    assert @conn.table_exists?(:rails_pulse_jobs), "jobs table missing"
    assert @conn.table_exists?(:rails_pulse_job_runs), "job_runs table missing"
  end

  test "upgrade from v0.3.1 creates deployments table" do
    load_baseline(RailsPulse::TestSchemas::V031)
    run_all_migrations

    assert @conn.table_exists?(:rails_pulse_deployments), "deployments table missing"
  end

  test "upgrade from v0.3.1 adds actual_sql to operations" do
    load_baseline(RailsPulse::TestSchemas::V031)
    run_all_migrations

    assert @conn.column_exists?(:rails_pulse_operations, :actual_sql), "actual_sql missing on operations"
  end

  test "upgrade from v0.3.1 leaves existing columns intact" do
    load_baseline(RailsPulse::TestSchemas::V031)
    run_all_migrations

    assert @conn.column_exists?(:rails_pulse_jobs, :p95_duration)
    assert @conn.column_exists?(:rails_pulse_operations, :row_count)
    assert @conn.column_exists?(:rails_pulse_requests, :response_size_bytes)
  end

  # Edge Cases

  test "migrations are idempotent when run against current schema" do
    run_all_migrations

    assert @conn.table_exists?(:rails_pulse_deployments)
    assert @conn.table_exists?(:rails_pulse_job_runs)
    assert @conn.column_exists?(:rails_pulse_operations, :actual_sql)
    assert @conn.column_exists?(:rails_pulse_jobs, :p95_duration)
  end

  # Record Insertion Tests

  test "can insert records after upgrading from v0.2.7" do
    load_baseline(RailsPulse::TestSchemas::V027)
    run_all_migrations

    assert_can_insert_core_records
    assert_can_insert_deployment
    assert_can_insert_job_run
  end

  test "can insert records after upgrading from v0.3.1" do
    load_baseline(RailsPulse::TestSchemas::V031)
    run_all_migrations

    assert_can_insert_core_records
    assert_can_insert_deployment
    assert_can_insert_job_run
  end

  private

  def load_baseline(schema_lambda)
    drop_all_rails_pulse_tables
    silence_schema_output { schema_lambda.call(@conn) }
    @conn.schema_cache.clear!
  end

  def run_all_migrations
    load_migration_files
    MIGRATION_CLASSES.each do |class_name|
      migration = class_name.constantize.new
      ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }
    end
    @conn.schema_cache.clear!
  end

  def load_migration_files
    Dir.glob("#{MIGRATE_DIR}/*.rb").sort.each { |f| load f }
  end

  def drop_all_rails_pulse_tables
    tables = @conn.tables.select { |t| t.start_with?("rails_pulse_") }
    @conn.disable_referential_integrity do
      tables.each { |t| @conn.drop_table(t, force: :cascade) }
    end
  end

  CURRENT_SCHEMA_FILE = File.expand_path("../../db/rails_pulse_schema.rb", __dir__)

  def restore_current_schema
    drop_all_rails_pulse_tables
    silence_schema_output { load CURRENT_SCHEMA_FILE }
    @conn.schema_cache.clear!
  end

  def silence_schema_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original_stdout
  end

  def assert_can_insert_core_records
    now = Time.current.iso8601(6)
    uuid = SecureRandom.uuid
    path = "/migration-test-#{SecureRandom.hex(4)}"

    @conn.execute(<<~SQL)
      INSERT INTO rails_pulse_routes (method, path, created_at, updated_at)
      VALUES ('GET', '#{path}', '#{now}', '#{now}')
    SQL

    route_id = @conn.select_value("SELECT id FROM rails_pulse_routes WHERE path = '#{path}'")

    assert route_id, "route insert failed"

    @conn.execute(<<~SQL)
      INSERT INTO rails_pulse_requests (route_id, duration, status, is_error, request_uuid, occurred_at, created_at, updated_at)
      VALUES (#{route_id}, 42.5, 200, 0, '#{uuid}', '#{now}', '#{now}', '#{now}')
    SQL

    request_count = @conn.select_value("SELECT COUNT(*) FROM rails_pulse_requests WHERE request_uuid = '#{uuid}'").to_i

    assert_equal 1, request_count, "request insert failed"
  end

  def assert_can_insert_job_run
    now = Time.current.iso8601(6)
    job_name = "MigrationTestJob-#{SecureRandom.hex(4)}"
    run_id = SecureRandom.uuid

    @conn.execute(<<~SQL)
      INSERT INTO rails_pulse_jobs (name, runs_count, failures_count, retries_count, created_at, updated_at)
      VALUES ('#{job_name}', 0, 0, 0, '#{now}', '#{now}')
    SQL

    job_id = @conn.select_value("SELECT id FROM rails_pulse_jobs WHERE name = '#{job_name}'")
    assert job_id, "job insert failed"

    @conn.execute(<<~SQL)
      INSERT INTO rails_pulse_job_runs (job_id, run_id, status, attempts, occurred_at, created_at, updated_at)
      VALUES (#{job_id}, '#{run_id}', 'completed', 0, '#{now}', '#{now}', '#{now}')
    SQL

    count = @conn.select_value("SELECT COUNT(*) FROM rails_pulse_job_runs WHERE run_id = '#{run_id}'").to_i
    assert_equal 1, count, "job_run insert failed"
  end

  def assert_can_insert_deployment
    now = Time.current.iso8601(6)

    @conn.execute(<<~SQL)
      INSERT INTO rails_pulse_deployments (revision, started_at, created_at, updated_at)
      VALUES ('abc123', '#{now}', '#{now}', '#{now}')
    SQL

    count = @conn.select_value("SELECT COUNT(*) FROM rails_pulse_deployments WHERE revision = 'abc123'").to_i

    assert_equal 1, count, "deployment insert failed"
  end
end
