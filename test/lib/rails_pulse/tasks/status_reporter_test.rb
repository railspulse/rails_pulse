require "test_helper"

class RailsPulse::Tasks::StatusReporterTest < ActiveSupport::TestCase
  fixtures :rails_pulse_summaries, :rails_pulse_events

  def setup
    super
    @output = StringIO.new
    RailsPulse::SchemaCheck.reset!
  end

  def teardown
    RailsPulse::SchemaCheck.reset!
    super
  end

  # Structure Tests

  test "reports every section against the dummy app" do
    report

    assert_match(/\ARails Pulse #{Regexp.escape(RailsPulse::VERSION)}/, @output.string)
    %w[Database: Schema: Migrations: Routes: Initializer: Tracking: Dashboard: API: Writer: Summaries: Retention: Cleanup: Jobs: Cloud:].each do |label|
      assert_includes @output.string, label
    end
  end

  test "returns true and says OK when nothing needs action" do
    assume_clean_install

    assert report
    assert_includes @output.string, "Schema:     up to date"
    assert_includes @output.string, "Migrations: none pending"
    assert_includes @output.string, "OK — nothing to do."
    assert_not_includes @output.string, "Action needed"
  end

  test "writer heartbeats are summed across processes" do
    assume_clean_install

    assert report
    assert_match(/Writer:     2 live process\(es\), queue depth 15\/1000, 0 request\(s\) dropped in the last hour/, @output.string)
  end

  test "no heartbeats yet is called out but is not an action" do
    assume_clean_install
    RailsPulse::Event.delete_all

    assert report
    assert_includes @output.string, "Writer:     no heartbeats yet"
  end

  # Action Tests

  test "requests dropped in the last hour fail the report" do
    assume_clean_install
    rails_pulse_events(:web_two_latest).update!(value: 7)

    assert_not report
    assert_match(/Writer:     2 live process\(es\).*7 request\(s\) dropped in the last hour/, @output.string)
    assert_match(/Action needed:.*dropped 7 request\(s\) in the last hour. Raise config.async_queue_size/m, @output.string)
  end

  test "schema drift is reported with the upgrade commands and fails the report" do
    assume_clean_install
    RailsPulse::SchemaCheck.stubs(:expected_schema).returns("rails_pulse_routes" => %w[http_methods ghost])

    assert_not report
    assert_includes @output.string, "Schema:     BEHIND this gem version"
    assert_includes @output.string, "rails_pulse_routes: missing ghost"
    assert_includes @output.string, "Routes:     (skipped — schema is behind)"
    assert_match(/Action needed:.*rails generate rails_pulse:upgrade/m, @output.string)
  end

  test "migration files present but not run are listed" do
    assume_clean_install
    RailsPulse::Tasks::StatusReporter.any_instance.stubs(:pending_migrations).returns([ "20990101000000_future_change.rb" ])

    assert_not report
    assert_includes @output.string, "1 migration file(s) present but not run"
    assert_includes @output.string, "20990101000000_future_change.rb"
    assert_match(/Run pending migrations: rails db:migrate/, @output.string)
  end

  test "gem migrations not yet copied into the app point at the upgrade generator" do
    assume_clean_install
    RailsPulse::Tasks::StatusReporter.any_instance.stubs(:gem_migrations_not_in_host).returns([ "20990101000000_new_feature.rb" ])

    assert_not report
    assert_includes @output.string, "not yet copied into this app"
    assert_match(/Copy this version's migrations: rails generate rails_pulse:upgrade/, @output.string)
  end

  test "an outstanding route backfill is reported" do
    assume_clean_install
    RailsPulse::Route.stubs(:needs_action_backfill?).returns(true)

    assert_not report
    assert_includes @output.string, "actions NOT backfilled"
    assert_match(/rails rails_pulse:migrate_routes/, @output.string)
  end

  test "initializer settings this version added but the host does not mention are listed" do
    assume_clean_install
    RailsPulse::Installers::ConfigUpdater.stubs(:missing).returns(keys: %w[authorize], hash_keys: %w[rails_pulse_deployments])

    assert_not report
    assert_includes @output.string, "2 setting(s) from this version not mentioned: authorize, rails_pulse_deployments"
    assert_match(/Append the new settings to the initializer/, @output.string)
  end

  test "a missing initializer points at the install generator" do
    assume_clean_install
    Rails.stubs(:root).returns(Pathname.new(Dir.mktmpdir))

    assert_not report
    assert_includes @output.string, "config/initializers/rails_pulse.rb not found"
    assert_match(/rails generate rails_pulse:install/, @output.string)
  end

  # Edge Cases

  test "stale summaries are a suggestion, not an action" do
    assume_clean_install
    RailsPulse::Summary.stubs(:maximum).returns(3.hours.ago)

    assert report
    assert_match(/Summaries:  last generated 3h ago — stale/, @output.string)
    assert_match(/Suggestions:.*RailsPulse::SummaryJob last ran 3h ago/m, @output.string)
  end

  test "no summaries at all is a suggestion, not an action" do
    assume_clean_install
    RailsPulse::Summary.stubs(:maximum).returns(nil)

    assert report
    assert_includes @output.string, "Summaries:  none generated yet"
    assert_match(/Suggestions:.*Schedule RailsPulse::SummaryJob hourly/m, @output.string)
  end

  # Suggestion Tests

  test "hourly summaries with no gaps are counted" do
    assume_clean_install
    overall_hours(3.hours.ago, 2.hours.ago, 1.hour.ago)

    assert report
    assert_includes @output.string, "hourly: 3 consecutive hour(s) summarized"
    assert_not_includes @output.string, "SummaryJob skipped"
  end

  test "hours SummaryJob skipped are a suggestion to backfill" do
    assume_clean_install
    # 4 hours from oldest to newest, 1 of them missing
    overall_hours(4.hours.ago, 3.hours.ago, 1.hour.ago)

    assert report
    assert_includes @output.string, "hourly: 3 of the last 4 hours summarized, 1 missing"
    assert_match(/Suggestions:.*SummaryJob skipped 1 hour\(s\) in the last 4.*backfill_summaries/m, @output.string)
  end

  test "hourly summaries past retention are not counted as gaps" do
    assume_clean_install
    overall_hours(10.days.ago, 2.hours.ago, 1.hour.ago)

    assert report
    assert_includes @output.string, "hourly: 2 consecutive hour(s) summarized"
  end

  test "hourly summary retention under a week is a suggestion" do
    assume_clean_install

    with_config(hourly_summary_retention: 2.days) do
      assert report
    end
    assert_includes @output.string, "Retention:  raw data 14 days, hourly summaries 2 days"
    assert_match(/Suggestions:.*config.hourly_summary_retention = 7.days/m, @output.string)
  end

  test "hourly summary retention of a week is not a suggestion" do
    assume_clean_install

    with_config(hourly_summary_retention: 7.days) do
      report
    end

    assert_not_includes @output.string, "hourly_summary_retention"
  end

  test "a recent cleanup run is reported with what it deleted" do
    assume_clean_install
    cleanup_run(3.hours.ago, deleted: 120)

    report

    assert_includes @output.string, "Cleanup:    last ran 3h ago, 120 row(s) deleted"
  end

  test "a cleanup run older than two days is a suggestion" do
    assume_clean_install
    cleanup_run(72.hours.ago)

    assert report
    assert_includes @output.string, "Cleanup:    last ran 3d ago — stale"
    assert_match(/Suggestions:.*schedule RailsPulse::CleanupJob daily/m, @output.string)
  end

  test "a failed cleanup run names the stages" do
    assume_clean_install
    cleanup_run(1.hour.ago, failed_stages: [ "requests (time_based)" ])

    assert report
    assert_includes @output.string, "Cleanup:    last ran 1h ago and failed (requests (time_based))"
    assert_match(/Suggestions:.*The last cleanup failed in requests \(time_based\)/m, @output.string)
  end

  test "no cleanup run with nothing past retention is not a suggestion" do
    assume_clean_install
    RailsPulse::CleanupRun.events.delete_all
    RailsPulse::Request.where(occurred_at: ...15.days.ago).delete_all

    report

    assert_includes @output.string, "Cleanup:    no run recorded yet"
    assert_not_includes @output.string, "data past retention is not being pruned"
  end

  test "no cleanup run while requests past retention are held is a suggestion" do
    assume_clean_install
    route = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/status-old", controller_action: "status#old")
    RailsPulse::Request.create!(route: route, duration: 10, status: 200, request_uuid: SecureRandom.uuid, occurred_at: 20.days.ago)

    assert report
    assert_includes @output.string, "requests older than 14 days are still held"
    assert_match(/Suggestions:.*data past retention is not being pruned/m, @output.string)
  end

  test "cleanup turned off says nothing is pruned" do
    assume_clean_install

    with_config(archiving_enabled: false) do
      report
    end

    assert_includes @output.string, "Cleanup:    off (config.archiving_enabled = false)"
  end

  test "untracked jobs are a suggestion" do
    assume_clean_install

    with_config(track_jobs: false) do
      assert report
    end
    assert_includes @output.string, "Jobs:       not tracked"
    assert_match(/Suggestions:.*config.track_jobs = true/m, @output.string)
  end

  test "tracked jobs are counted" do
    assume_clean_install
    RailsPulse::Job.create!(name: "StatusCountedJob", queue_name: "default")

    with_config(track_jobs: true) do
      report
    end

    assert_match(/Jobs:       tracked, \d+ job class\(es\) recorded/, @output.string)
  end

  test "suggestions follow the OK line and do not fail the report" do
    assume_clean_install

    with_config(track_jobs: false) do
      assert report
    end
    assert_operator @output.string.index("OK — nothing to do."), :<, @output.string.index("Suggestions:")
  end

  test "Cloud is reported off until the key and application are set" do
    assume_clean_install

    assert report
    assert_includes @output.string, "Cloud:      off"
  end

  test "Cloud reports the last accepted sync and the buffer" do
    assume_clean_install
    RailsPulse::Cloud::Installation.delete_all
    RailsPulse::Cloud::BufferedBatch.delete_all
    RailsPulse::Cloud::Installation.current.update!(last_success_at: 3.minutes.ago, last_health_at: 1.minute.ago)

    with_cloud { assert report }

    assert_match(/Cloud:      shop \(test\) to https:\/\/ingest\.railspulse\.com: connected, last accepted 3m ago; 0 batch\(es\) buffered/, @output.string)
    assert_not_includes @output.string, "CloudHealthJob"
  end

  test "a paused Cloud sync is a suggestion, not an action" do
    assume_clean_install
    RailsPulse::Cloud::Installation.delete_all
    installation = RailsPulse::Cloud::Installation.current
    installation.pause!(1.hour.from_now, "Rails Pulse Cloud refused config.cloud.api_key: That key has been revoked.")
    installation.update!(last_health_at: 1.minute.ago, contract_deprecated_on: "2027-10-01")

    with_cloud { assert report }

    assert_includes @output.string, "paused until"
    assert_match(/Suggestions:.*That key has been revoked\./m, @output.string)
    assert_includes @output.string, "stops accepting this gem's sync contract on 2027-10-01"
  end

  test "Cloud configured without its tables suggests install_cloud" do
    assume_clean_install
    RailsPulse::Cloud::Installation.stubs(:table_exists?).returns(false)

    with_cloud { assert report }

    assert_includes @output.string, "its tables are not installed"
    assert_match(/Suggestions:.*rails generate rails_pulse:install_cloud/m, @output.string)
  end

  test "Cloud without recent health updates suggests scheduling CloudHealthJob" do
    assume_clean_install
    RailsPulse::Cloud::Installation.delete_all

    with_cloud { assert report }

    assert_includes @output.string, "not synced yet"
    assert_match(/Suggestions:.*RailsPulse::CloudHealthJob every minute/m, @output.string)
  end

  private

  def with_cloud
    cloud = RailsPulse.configuration.cloud
    saved = cloud.to_h
    cloud.api_key = "rpc_4f9Kx2mQ8vTzL1nB7wYc3HdR6sJe5PaU"
    cloud.application = "shop"
    cloud.environment = "test"
    yield
  ensure
    saved.each { |key, value| cloud.public_send(:"#{key}=", value) }
  end

  def with_config(settings)
    original = settings.keys.to_h { |key| [ key, RailsPulse.configuration.public_send(key) ] }
    settings.each { |key, value| RailsPulse.configuration.public_send("#{key}=", value) }
    yield
  ensure
    original.each { |key, value| RailsPulse.configuration.public_send("#{key}=", value) }
  end

  def overall_hours(*times)
    RailsPulse::Summary.overall_requests.where(period_type: "hour").delete_all
    times.each do |time|
      start = time.beginning_of_hour
      RailsPulse::Summary.create!(
        summarizable_type: "RailsPulse::Request", summarizable_id: 0, period_type: "hour",
        period_start: start, period_end: start.end_of_hour, count: 0
      )
    end
  end

  def cleanup_run(at, deleted: 0, failed_stages: [])
    RailsPulse::CleanupRun.events.delete_all
    RailsPulse::CleanupRun.record!(
      stats: { time_based: {}, count_based: {}, total_deleted: deleted }, failed_stages: failed_stages, ran_at: at
    )
  end

  def report
    RailsPulse::Tasks::StatusReporter.report(output: @output)
  end

  # The dummy app is not a host app: it has no config/initializers/rails_pulse.rb
  # at Rails.root's expected place in every worker, its migrations live in
  # test/dummy/db/migrate, and fixtures may leave routes without actions.
  # Pin those so each test controls exactly one variable.
  def assume_clean_install
    RailsPulse::Tasks::StatusReporter.any_instance.stubs(:gem_migrations_not_in_host).returns([])
    RailsPulse::Tasks::StatusReporter.any_instance.stubs(:pending_migrations).returns([])
    RailsPulse::Route.stubs(:needs_action_backfill?).returns(false)
    RailsPulse::RouteIndexes.stubs(:exists?).returns(true)
    RailsPulse::Installers::ConfigUpdater.stubs(:missing).returns(keys: [], hash_keys: [])
    RailsPulse::Summary.stubs(:maximum).returns(5.minutes.ago)
  end
end
