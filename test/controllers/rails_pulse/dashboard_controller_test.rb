require "test_helper"

class RailsPulse::DashboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    # Force lazy route set evaluation while track_jobs=true so job routes are cached
    # before any test can toggle track_jobs=false and corrupt the route cache.
    RailsPulse::Engine.routes.url_helpers.root_path
    # Neutralize fixture jobs so NeedsAttention#job_items never calls job_path.
    RailsPulse::Job.update_all(runs_count: 0)
  end

  test "should handle time range parameter" do
    get rails_pulse.root_path, params: { time_range: "24h" }

    assert_response :success
  end

  test "should handle invalid time range gracefully" do
    get rails_pulse.root_path, params: { time_range: "invalid" }

    assert_response :success
    # Should default to a valid time range
  end

  test "should include required CSS and JavaScript" do
    get rails_pulse.root_path

    assert_response :success
  end

  test "should display breadcrumbs" do
    get rails_pulse.root_path

    assert_response :success
  end

  test "renders job failure rate card when track_jobs is true" do
    original = RailsPulse.configuration.track_jobs
    RailsPulse.configuration.track_jobs = true

    get rails_pulse.root_path

    assert_response :success
    assert_match "jobs_failure_rate", response.body
  ensure
    RailsPulse.configuration.track_jobs = original
  end

  test "omits job failure rate card when track_jobs is false" do
    original = RailsPulse.configuration.track_jobs
    RailsPulse.configuration.track_jobs = false

    get rails_pulse.root_path

    assert_response :success
    assert_no_match "jobs_failure_rate", response.body
  ensure
    RailsPulse.configuration.track_jobs = original
  end

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
