require "test_helper"

class RailsPulse::StorageControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_requests,
           :rails_pulse_operations, :rails_pulse_summaries

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
  end

  test "show responds successfully" do
    get rails_pulse.storage_path

    assert_response :success
  end

  test "show assigns status" do
    get rails_pulse.storage_path

    assert_not_nil assigns(:status)
    assert_kind_of RailsPulse::Dashboard::StorageStatus, assigns(:status)
  end

  test "show lists pulse tables" do
    get rails_pulse.storage_path

    assert_response :success
    assert_includes response.body, "Operations"
    assert_includes response.body, "Requests"
    assert_includes response.body, "Queries"
  end

  test "show includes cleanup and database sections" do
    get rails_pulse.storage_path

    assert_response :success
    assert_includes response.body, "Cleanup"
    assert_includes response.body, "Database"
  end

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
