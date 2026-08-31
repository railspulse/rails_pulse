require "test_helper"
require "rake"

class RailsPulseAssetsRakeTest < ActiveSupport::TestCase
  # Disable parallelization for rake task tests
  parallelize(workers: 1)

  def self.load_rake_tasks_once
    return if defined?(@@assets_tasks_loaded)

    # The assets:precompile enhance hook only registers when the task exists at
    # load time. The test environment does not define it, and another task-test
    # class may have already loaded the rake tasks (Rails.application.load_tasks
    # is idempotent), so re-load the assets file after providing a stand-in —
    # this guarantees the hook is registered regardless of class load order.
    Rake::Task.define_task("assets:precompile") unless Rake::Task.task_defined?("assets:precompile")
    load File.expand_path("../../../lib/tasks/rails_pulse_assets.rake", __dir__)

    @@assets_tasks_loaded = true
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

  test "install_assets copies packaged assets and reports the count" do
    RailsPulse::PackagedAssets.stubs(:install!).returns([ "a.js", "b.css" ])

    output = reenable_and_capture("rails_pulse:install_assets") do
      Rake::Task["rails_pulse:install_assets"].invoke
    end

    assert_includes output, "Installed 2 dashboard assets into public/assets"
  end

  test "assets:precompile triggers the install_assets enhancement" do
    RailsPulse::PackagedAssets.stubs(:install!).returns([])
    # Rake tasks invoke once per process — the other test may have already
    # invoked install_assets, which the enhancement calls.
    Rake::Task["rails_pulse:install_assets"].reenable

    output = reenable_and_capture("assets:precompile") do
      Rake::Task["assets:precompile"].invoke
    end

    assert_includes output, "Installed 0 dashboard assets into public/assets"
  end
end
