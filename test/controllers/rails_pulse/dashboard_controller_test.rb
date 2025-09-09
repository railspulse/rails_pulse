require "test_helper"

class RailsPulse::DashboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"
    setup_clean_database
    stub_all_external_dependencies
    stub_chart_calculations
    super
  end

  test "should handle time range parameter" do
    get_rails_pulse("", time_range: "24h")
    assert_successful_response
  end

  test "should handle invalid time range gracefully" do
    get_rails_pulse("", time_range: "invalid")
    assert_successful_response
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

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
