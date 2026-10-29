require "test_helper"

# The header's time range selector is rendered by the layout on every page,
# while each page picks its own default range. With no stored preference the
# selector must name the range the page actually resolved.
class RailsPulse::TimeRangeSelectorDefaultsTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  fixtures :rails_pulse_routes, :rails_pulse_requests, :rails_pulse_queries, :rails_pulse_jobs,
           :rails_pulse_summaries, :rails_pulse_deployments, :rails_pulse_exception_groups,
           :rails_pulse_exception_occurrences

  LABEL = "[data-rails-pulse--time-range-target=label]".freeze

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    RailsPulse::Engine.routes.url_helpers.root_path
    RailsPulse::Job.update_all(runs_count: 0)
  end

  # Structure Tests

  test "dashboard names its 24 hour default" do
    get rails_pulse.root_path

    assert_response :success
    assert_select LABEL, text: "Last 24 hours"
  end

  test "requests names its 24 hour default" do
    get rails_pulse.requests_path

    assert_response :success
    assert_select LABEL, text: "Last 24 hours"
  end

  test "routes names its 14 day default" do
    get rails_pulse.routes_path

    assert_response :success
    assert_select LABEL, text: "Last 14 days"
    assert_equal "last_14_days", assigns(:time_range).selected_time_range
  end

  test "queries names its 7 day default" do
    get rails_pulse.queries_path

    assert_response :success
    assert_select LABEL, text: "Last 7 days"
    assert_equal "last_7_days", assigns(:time_range).selected_time_range
  end

  test "jobs names its 7 day default" do
    get rails_pulse.jobs_path

    assert_response :success
    assert_select LABEL, text: "Last 7 days"
  end

  test "exceptions names its 7 day default" do
    get rails_pulse.exceptions_path

    assert_response :success
    assert_select LABEL, text: "Last 7 days"
  end

  # Edge Cases

  test "a stored preference is shown instead of the page default" do
    patch rails_pulse.settings_time_range_path, params: { preset: "last_30_days" }
    get rails_pulse.queries_path

    assert_response :success
    assert_select LABEL, text: "Last 30 days"
  end
end
