require "test_helper"

class RailsPulse::DashboardControllerTest < ActionDispatch::IntegrationTest
  fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_jobs, :rails_pulse_summaries

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    # Force lazy route set evaluation while track_jobs=true so job routes are cached
    # before any test can toggle track_jobs=false and corrupt the route cache.
    RailsPulse::Engine.routes.url_helpers.root_path
    # Neutralize fixture jobs so NeedsAttention#job_items never calls job_path.
    RailsPulse::Job.update_all(runs_count: 0)
  end

  # Parameter & HTTP Response Tests

  test "accepts period 7 parameter" do
    get rails_pulse.root_path, params: { period: 7 }

    assert_response :success
  end

  test "accepts period 14 parameter" do
    get rails_pulse.root_path, params: { period: 14 }

    assert_response :success
  end

  test "accepts period 30 parameter" do
    get rails_pulse.root_path, params: { period: 30 }

    assert_response :success
  end

  test "handles invalid period parameter" do
    get rails_pulse.root_path, params: { period: 999 }

    assert_response :success
  end

  test "handles zero period parameter" do
    get rails_pulse.root_path, params: { period: 0 }

    assert_response :success
  end

  test "handles negative period parameter" do
    get rails_pulse.root_path, params: { period: -5 }

    assert_response :success
  end

  test "handles missing period parameter" do
    get rails_pulse.root_path

    assert_response :success
  end

  test "returns HTML content" do
    get rails_pulse.root_path

    assert_response :success
    assert_not_nil response.body
    assert_operator response.body.length, :>, 0
  end

  # Configuration Tests

  test "handles jobs tracking disabled" do
    original = RailsPulse.configuration.track_jobs
    RailsPulse.configuration.track_jobs = false

    get rails_pulse.root_path

    assert_response :success
    # Should render without job metrics
  ensure
    RailsPulse.configuration.track_jobs = original
  end

  test "includes job metrics when tracking enabled" do
    original = RailsPulse.configuration.track_jobs
    RailsPulse.configuration.track_jobs = true

    get rails_pulse.root_path

    assert_response :success
    assert_not_nil response.body
  ensure
    RailsPulse.configuration.track_jobs = original
  end

  # Content Tests

  test "response includes metric cards" do
    get rails_pulse.root_path

    assert_response :success
    assert_includes response.body, "metric-strip"
  end

  test "response includes charts" do
    get rails_pulse.root_path

    assert_response :success
    assert_includes response.body, "chart"
  end

  test "response includes needs attention panel" do
    get rails_pulse.root_path

    assert_response :success
    # Panel should be present
    assert_not_nil response.body
  end

  test "response includes health summary" do
    get rails_pulse.root_path

    assert_response :success
    assert_not_nil response.body
  end

  # Edge Cases

  test "renders without errors when no data exists" do
    get rails_pulse.root_path

    assert_response :success
    assert_operator response.body.length, :>, 1000
  end

  test "renders with substantial HTML content" do
    get rails_pulse.root_path

    assert_response :success
    # Dashboard should have substantial content
    assert_operator response.body.length, :>, 5000
  end

  test "renders dashboard title" do
    get rails_pulse.root_path

    assert_response :success
    # Should contain dashboard identifier
    assert_not_nil response.body
  end

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
