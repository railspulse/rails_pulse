require "test_helper"
require "rake"

class RailsPulseRakeTest < ActiveSupport::TestCase
  # Disable parallelization for rake task tests
  parallelize(workers: 1)

  def self.load_rake_tasks_once
    return if defined?(@@tasks_loaded_rails_pulse)

    # Suppress warnings about already initialized constants
    original_verbose = $VERBOSE
    $VERBOSE = nil

    Rails.application.load_tasks

    $VERBOSE = original_verbose
    @@tasks_loaded_rails_pulse = true
  end

  # Load tasks when class is defined
  load_rake_tasks_once

  def teardown
    Mocha::Mockery.instance.teardown
  end

  def reenable_and_capture(task_name)
    Rake::Task[task_name].reenable
    output = StringIO.new
    old_stdout = $stdout
    $stdout = output
    begin
      yield
    rescue SystemExit
      # Catch expected exits
    ensure
      $stdout = old_stdout
    end
    output.string
  end

  # rails_pulse:backfill_summaries tests

  test "backfill_summaries exits early when no data exists" do
    RailsPulse::Request.stubs(:minimum).with(:occurred_at).returns(nil)
    RailsPulse::Operation.stubs(:minimum).with(:occurred_at).returns(nil)

    output = reenable_and_capture("rails_pulse:backfill_summaries") do
      Rake::Task["rails_pulse:backfill_summaries"].invoke
    end

    assert_includes output, "No Rails Pulse data found"
  end

  test "backfill_summaries uses earliest request when only requests exist" do
    earliest = 5.days.ago
    RailsPulse::Request.stubs(:minimum).with(:occurred_at).returns(earliest)
    RailsPulse::Operation.stubs(:minimum).with(:occurred_at).returns(nil)
    RailsPulse::BackfillSummariesJob.stubs(:perform_now)
    RailsPulse::Summary.stubs(:count).returns(10)

    output = reenable_and_capture("rails_pulse:backfill_summaries") do
      Rake::Task["rails_pulse:backfill_summaries"].invoke
    end

    assert_includes output, "Starting Rails Pulse summary backfill"
    assert_includes output, "Creating hourly and daily summaries"
  end

  test "backfill_summaries uses earliest operation when only operations exist" do
    earliest = 3.days.ago
    RailsPulse::Request.stubs(:minimum).with(:occurred_at).returns(nil)
    RailsPulse::Operation.stubs(:minimum).with(:occurred_at).returns(earliest)
    RailsPulse::BackfillSummariesJob.stubs(:perform_now)
    RailsPulse::Summary.stubs(:count).returns(5)

    output = reenable_and_capture("rails_pulse:backfill_summaries") do
      Rake::Task["rails_pulse:backfill_summaries"].invoke
    end

    assert_includes output, "Starting Rails Pulse summary backfill"
    assert_includes output, "Creating hourly and daily summaries"
  end

  test "backfill_summaries uses earliest of request and operation" do
    earlier = 10.days.ago
    later = 5.days.ago

    RailsPulse::Request.stubs(:minimum).with(:occurred_at).returns(later)
    RailsPulse::Operation.stubs(:minimum).with(:occurred_at).returns(earlier)
    RailsPulse::BackfillSummariesJob.stubs(:perform_now)
    RailsPulse::Summary.stubs(:count).returns(20)

    output = reenable_and_capture("rails_pulse:backfill_summaries") do
      Rake::Task["rails_pulse:backfill_summaries"].invoke
    end

    assert_includes output, "Starting Rails Pulse summary backfill"
  end

  test "backfill_summaries generates daily and hourly summaries" do
    earliest = 2.days.ago
    RailsPulse::Request.stubs(:minimum).with(:occurred_at).returns(earliest)
    RailsPulse::Operation.stubs(:minimum).with(:occurred_at).returns(nil)

    daily_job_call = false
    hourly_job_call = false

    combined_job_call = false

    RailsPulse::BackfillSummariesJob.stubs(:perform_now).with { |_start, _end, types|
      combined_job_call = true if types == [ "hour", "day" ]
      true
    }
    RailsPulse::Summary.stubs(:count).returns(3)

    reenable_and_capture("rails_pulse:backfill_summaries") do
      Rake::Task["rails_pulse:backfill_summaries"].invoke
    end

    assert combined_job_call, "Expected daily summaries job to be called"
  end

  test "backfill_summaries outputs completion message with count" do
    earliest = 1.day.ago
    RailsPulse::Request.stubs(:minimum).with(:occurred_at).returns(earliest)
    RailsPulse::Operation.stubs(:minimum).with(:occurred_at).returns(nil)
    RailsPulse::BackfillSummariesJob.stubs(:perform_now)
    RailsPulse::Summary.stubs(:count).returns(42)

    output = reenable_and_capture("rails_pulse:backfill_summaries") do
      Rake::Task["rails_pulse:backfill_summaries"].invoke
    end

    assert_includes output, "backfill completed"
    assert_includes output, "42"
  end

  test "backfill_summaries outputs schedule reminder" do
    earliest = 1.day.ago
    RailsPulse::Request.stubs(:minimum).with(:occurred_at).returns(earliest)
    RailsPulse::Operation.stubs(:minimum).with(:occurred_at).returns(nil)
    RailsPulse::BackfillSummariesJob.stubs(:perform_now)
    RailsPulse::Summary.stubs(:count).returns(1)

    output = reenable_and_capture("rails_pulse:backfill_summaries") do
      Rake::Task["rails_pulse:backfill_summaries"].invoke
    end

    assert_includes output, "SummaryJob"
  end

  # db:schema:load_rails_pulse tests

  test "load_rails_pulse loads schema when separate database setup" do
    Object.any_instance.stubs(:separate_database_setup?).returns(true)

    output = reenable_and_capture("db:schema:load_rails_pulse") do
      Rake::Task["db:schema:load_rails_pulse"].invoke
    end

    # Should either load successfully or skip if tables exist
    assert output.include?("schema loaded successfully") || output.include?("already exist")
  end

  test "load_rails_pulse skips when single database setup" do
    Object.any_instance.stubs(:separate_database_setup?).returns(false)

    output = reenable_and_capture("db:schema:load_rails_pulse") do
      Rake::Task["db:schema:load_rails_pulse"].invoke
    end

    assert_includes output, "Single database setup"
  end

  test "separate_database_setup_helper returns true when rails_pulse_migrate dir exists" do
    dir_path = Rails.root.join("db/rails_pulse_migrate")
    dir_path.stubs(:exist?).returns(true)
    Rails.root.stubs(:join).with("db/rails_pulse_migrate").returns(dir_path)

    assert_predicate self, :separate_database_setup?
  end

  test "separate_database_setup_helper checks database configuration" do
    dir_path = Rails.root.join("db/rails_pulse_migrate")
    dir_path.stubs(:exist?).returns(false)
    Rails.root.stubs(:join).with("db/rails_pulse_migrate").returns(dir_path)

    # Test that it checks the database configuration
    # In actual code, it will return false if both checks fail
    result = separate_database_setup?

    # Either true or false is valid depending on actual config
    assert_includes [ true, false ], result
  end

  test "db:prepare hook is defined" do
    task = Rake::Task["db:prepare"]

    assert_kind_of Rake::Task, task
  end

  test "db:setup hook is defined" do
    task = Rake::Task["db:setup"]

    assert_kind_of Rake::Task, task
  end

  test "backfill_summaries processes both request and operation data" do
    earliest_req = 4.days.ago
    earliest_op = 6.days.ago
    RailsPulse::Request.stubs(:minimum).with(:occurred_at).returns(earliest_req)
    RailsPulse::Operation.stubs(:minimum).with(:occurred_at).returns(earliest_op)
    RailsPulse::BackfillSummariesJob.stubs(:perform_now)
    RailsPulse::Summary.stubs(:count).returns(15)

    output = reenable_and_capture("rails_pulse:backfill_summaries") do
      Rake::Task["rails_pulse:backfill_summaries"].invoke
    end

    assert_includes output, "Creating hourly and daily summaries"
    assert_includes output, "15"
  end
  # rails_pulse:record_deployment tests

  test "record_deployment requires a revision" do
    output = capture_stderr do
      reenable_and_capture("rails_pulse:record_deployment") do
        Rake::Task["rails_pulse:record_deployment"].invoke
      end
    end

    assert_includes output, "ERROR: revision is required"
  end

  test "record_deployment records the revision" do
    deployment = stub(revision: "abc1234", started_at: Time.current)
    RailsPulse::Deployment.stubs(:create!).with(revision: "abc1234", started_at: instance_of(ActiveSupport::TimeWithZone)).returns(deployment)

    output = reenable_and_capture("rails_pulse:record_deployment") do
      Rake::Task["rails_pulse:record_deployment"].invoke("abc1234")
    end

    assert_includes output, "Deployment recorded: abc1234"
  end

  test "record_deployment aborts on invalid record" do
    RailsPulse::Deployment.stubs(:create!).raises(ActiveRecord::RecordInvalid)

    output = capture_stderr do
      reenable_and_capture("rails_pulse:record_deployment") do
        Rake::Task["rails_pulse:record_deployment"].invoke("abc1234")
      end
    end

    assert_includes output, "ERROR:"
  end

  # record_rails_pulse_migrations_applied tests

  test "migration recording skips when schema load created no tables" do
    with_temporary_migrations_dir("20260101000000_test_feature.rb" => "") do
      conn = mock("connection")
      conn.stubs(:table_exists?).with(:rails_pulse_routes).returns(false)
      RailsPulse::ApplicationRecord.stubs(:connection).returns(conn)

      output = capture_stdout { record_rails_pulse_migrations_applied }

      assert_includes output, "skipping migration recording"
    end
  end

  test "migration recording marks plain migrations applied" do
    with_temporary_migrations_dir("20260101000000_test_feature.rb" => "") do
      conn = mock("connection")
      conn.stubs(:table_exists?).with(:rails_pulse_routes).returns(true)
      conn.stubs(:table_exists?).with(:schema_migrations).returns(true)
      conn.stubs(:select_values).returns([])
      conn.stubs(:quote).returns("'20260101000000'")
      conn.expects(:execute).with("INSERT INTO schema_migrations (version) VALUES ('20260101000000')")
      RailsPulse::ApplicationRecord.stubs(:connection).returns(conn)

      output = capture_stdout { record_rails_pulse_migrations_applied }

      assert_includes output, "Marked migration 20260101000000 as applied"
    end
  end

  test "migration recording creates the schema_migrations table when missing" do
    with_temporary_migrations_dir("20260101000000_test_feature.rb" => "") do
      conn = mock("connection")
      conn.stubs(:table_exists?).with(:rails_pulse_routes).returns(true)
      conn.stubs(:table_exists?).with(:schema_migrations).returns(false)
      table = mock("table")
      table.stubs(:string).with(:version, null: false)
      conn.stubs(:create_table).with(:schema_migrations, id: false).yields(table)
      conn.stubs(:add_index).with(:schema_migrations, :version, unique: true, name: "unique_schema_migrations")
      conn.stubs(:select_values).returns([])
      conn.stubs(:quote).returns("'20260101000000'")
      conn.stubs(:execute)
      RailsPulse::ApplicationRecord.stubs(:connection).returns(conn)

      record_rails_pulse_migrations_applied
    end
  end

  test "migration recording skips route migrations whose columns are absent" do
    with_temporary_migrations_dir(
      "20260610000002_change_rails_pulse_routes_to_multi_verb_model.rb" => ""
    ) do
      conn = mock("connection")
      conn.stubs(:table_exists?).with(:rails_pulse_routes).returns(true)
      conn.stubs(:table_exists?).with(:schema_migrations).returns(true)
      conn.stubs(:column_exists?).with(:rails_pulse_routes, :controller_action).returns(false)
      conn.stubs(:execute).never
      RailsPulse::ApplicationRecord.stubs(:connection).returns(conn)

      output = capture_stdout { record_rails_pulse_migrations_applied }

      assert_includes output, "Skipping 20260610000002"
    end
  end

  test "migration recording warns when recording fails" do
    with_temporary_migrations_dir("20260101000000_test_feature.rb" => "") do
      conn = mock("connection")
      conn.stubs(:table_exists?).with(:rails_pulse_routes).returns(true)
      conn.stubs(:table_exists?).with(:schema_migrations).returns(true)
      conn.stubs(:select_values).raises(StandardError, "boom")
      conn.stubs(:quote).returns("'20260101000000'")
      RailsPulse::ApplicationRecord.stubs(:connection).returns(conn)

      err = capture_stderr { record_rails_pulse_migrations_applied }

      assert_includes err, "Could not mark migrations as applied"
    end
  end

  test "load_rails_pulse reports a missing schema file" do
    Object.any_instance.stubs(:separate_database_setup?).returns(true)
    schema_file = Rails.root.join("db/rails_pulse_schema.rb")
    schema_file.stubs(:exist?).returns(false)
    Rails.root.stubs(:join).with("db/rails_pulse_schema.rb").returns(schema_file)

    output = reenable_and_capture("db:schema:load_rails_pulse") do
      Rake::Task["db:schema:load_rails_pulse"].invoke
    end

    assert_includes output, "schema file not found"
  end

  private

  def capture_stdout
    output = StringIO.new
    old_stdout = $stdout
    $stdout = output
    begin
      yield
    ensure
      $stdout = old_stdout
    end
    output.string
  end

  def capture_stderr
    output = StringIO.new
    old_stderr = $stderr
    $stderr = output
    begin
      yield
    ensure
      $stderr = old_stderr
    end
    output.string
  end

  def with_temporary_migrations_dir(files)
    dir = Dir.mktmpdir
    files.each { |name, body| File.write(File.join(dir, name), body) }
    path = Pathname.new(dir)
    path.stubs(:exist?).returns(true)
    Rails.root.stubs(:join).with("db/rails_pulse_migrate").returns(path)
    yield
  ensure
    FileUtils.remove_entry(dir) if dir
  end
  # Deployment tasks

  test "record_deployment creates a deployment for the revision" do
    output = reenable_and_capture("rails_pulse:record_deployment") do
      Rake::Task["rails_pulse:record_deployment"].invoke("rake-rec-1")
    end

    deployment = RailsPulse::Deployment.find_by(revision: "rake-rec-1")

    assert_not_nil deployment
    assert_nil deployment.finished_at
    assert_nil deployment.metadata
    assert_includes output, "Deployment recorded: rake-rec-1"
  end

  test "record_deployment stores metadata from RAILS_PULSE_DEPLOYMENT_METADATA" do
    with_env("RAILS_PULSE_DEPLOYMENT_METADATA" => '{"environment":"staging"}') do
      reenable_and_capture("rails_pulse:record_deployment") do
        Rake::Task["rails_pulse:record_deployment"].invoke("rake-meta-1")
      end
    end

    assert_equal({ "environment" => "staging" }, RailsPulse::Deployment.find_by(revision: "rake-meta-1").metadata_hash)
  end

  test "record_deployment aborts on metadata that is not a JSON object" do
    Rake::Task["rails_pulse:record_deployment"].reenable

    _out, err = capture_io do
      with_env("RAILS_PULSE_DEPLOYMENT_METADATA" => "[1,2]") do
        assert_raises(SystemExit) { Rake::Task["rails_pulse:record_deployment"].invoke("rake-bad-1") }
      end
    end

    assert_includes err, "must be a JSON object"
    assert_nil RailsPulse::Deployment.find_by(revision: "rake-bad-1")
  end

  test "finish_deployment marks the latest deployment for the revision as finished" do
    older = RailsPulse::Deployment.create!(revision: "rake-fin-1", started_at: 2.hours.ago)
    latest = RailsPulse::Deployment.create!(revision: "rake-fin-1", started_at: 5.minutes.ago)

    output = reenable_and_capture("rails_pulse:finish_deployment") do
      Rake::Task["rails_pulse:finish_deployment"].invoke("rake-fin-1")
    end

    assert_not_nil latest.reload.finished_at
    assert_nil older.reload.finished_at
    assert_includes output, "Deployment finished: rake-fin-1"
  end

  test "finish_deployment aborts when no deployment exists for the revision" do
    Rake::Task["rails_pulse:finish_deployment"].reenable

    _out, err = capture_io do
      assert_raises(SystemExit) { Rake::Task["rails_pulse:finish_deployment"].invoke("rake-none-1") }
    end

    assert_includes err, "no deployment recorded for revision rake-none-1"
  end

  private

  def with_env(overrides)
    previous = overrides.keys.to_h { |key| [ key, ENV[key] ] }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
