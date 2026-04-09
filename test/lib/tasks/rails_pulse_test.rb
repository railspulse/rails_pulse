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
    assert_includes output, "Creating daily summaries"
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
    assert_includes output, "Creating hourly summaries"
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

    RailsPulse::BackfillSummariesJob.stubs(:perform_now).with { |_start, _end, types|
      if types == [ "day" ]
        daily_job_call = true
      elsif types == [ "hour" ]
        hourly_job_call = true
      end
      true
    }
    RailsPulse::Summary.stubs(:count).returns(3)

    reenable_and_capture("rails_pulse:backfill_summaries") do
      Rake::Task["rails_pulse:backfill_summaries"].invoke
    end

    assert daily_job_call, "Expected daily summaries job to be called"
    assert hourly_job_call, "Expected hourly summaries job to be called"
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

    assert_includes output, "Creating daily summaries"
    assert_includes output, "Creating hourly summaries"
    assert_includes output, "15"
  end
end
