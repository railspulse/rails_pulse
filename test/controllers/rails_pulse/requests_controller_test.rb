require "test_helper"

class RailsPulse::RequestsControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @request_record = rails_pulse_requests(:users_request_1)
  end

  # Controller Structure Tests

  test "controller includes required concerns" do
    assert_includes RailsPulse::RequestsController.included_modules, ChartTableConcern
    assert_includes RailsPulse::RequestsController.included_modules, TagFilterConcern
  end

  test "controller has index and show actions" do
    controller = RailsPulse::RequestsController.new

    assert_respond_to controller, :index
    assert_respond_to controller, :show
  end

  test "controller has required private methods" do
    controller = RailsPulse::RequestsController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :chart_model
    assert_includes private_methods, :table_model
    assert_includes private_methods, :chart_class
    assert_includes private_methods, :set_request
    assert_includes private_methods, :setup_metric_cards
    assert_includes private_methods, :build_chart_ransack_params
    assert_includes private_methods, :build_table_ransack_params
    assert_includes private_methods, :build_table_results
  end

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::RequestsController, :<, RailsPulse::ApplicationController
  end

  test "controller defines custom TIME_RANGE_OPTIONS" do
    expected_options = [
      [ "Recent", "recent" ],
      [ "Custom Range", "custom" ]
    ]

    assert_equal expected_options, RailsPulse::RequestsController::TIME_RANGE_OPTIONS
  end

  test "uses correct chart and table models" do
    controller = RailsPulse::RequestsController.new

    assert_equal RailsPulse::Summary, controller.send(:chart_model)
    assert_equal RailsPulse::Request, controller.send(:table_model)
  end

  test "uses correct chart class" do
    controller = RailsPulse::RequestsController.new

    assert_equal RailsPulse::Requests::Charts::AverageResponseTimes, controller.send(:chart_class)
  end

  test "chart options are empty for requests index" do
    controller = RailsPulse::RequestsController.new
    options = controller.send(:chart_options)

    assert_empty options
  end

  test "default table sort is by occurred_at descending" do
    controller = RailsPulse::RequestsController.new

    assert_equal "occurred_at desc", controller.send(:default_table_sort)
  end

  # Index Action Tests

  test "index action loads successfully" do
    get rails_pulse.requests_path

    assert_response :success
    # ChartTableConcern should set up these variables
    assert_not_nil assigns(:chart_data)
    assert_not_nil assigns(:table_data)
    assert_not_nil assigns(:pagy)
  end

  test "index action with ransack search by status" do
    get rails_pulse.requests_path, params: { q: { status_eq: 200 } }

    assert_response :success
    requests = assigns(:table_data)

    # All returned requests should have status 200
    assert requests.all? { |req| req.status == 200 }
  end

  test "index action with ransack search by controller_action" do
    get rails_pulse.requests_path, params: { q: { controller_action_cont: "Users" } }

    assert_response :success
    requests = assigns(:table_data)

    # Should have at least one request with "Users" in controller_action
    assert requests.any? { |req| req.controller_action.include?("Users") }
  end

  test "index action with error filter" do
    get rails_pulse.requests_path, params: { q: { is_error_eq: true } }

    assert_response :success
    requests = assigns(:table_data)

    # Should have at least one error request
    assert requests.any?(&:is_error)
  end

  test "index action respects pagination" do
    get rails_pulse.requests_path, params: { limit: 5 }

    assert_response :success
    pagy = assigns(:pagy)
    requests = assigns(:table_data)

    assert_not_nil pagy
    assert_operator requests.size, :<=, 5
  end

  test "index action with custom sorting" do
    get rails_pulse.requests_path, params: { q: { s: "duration asc" } }

    assert_response :success
    requests = assigns(:table_data)

    # Verify requests are ordered by duration asc
    if requests.size > 1
      requests.each_cons(2) do |current, next_req|
        assert_operator current.duration, :<=, next_req.duration
      end
    end
  end

  # Show Action Tests

  test "show action loads successfully" do
    get rails_pulse.request_path(@request_record)

    assert_response :success
    assert_not_nil assigns(:request)
    assert_not_nil assigns(:operation_timeline)
    assert_equal @request_record, assigns(:request)
  end

  test "show action creates operation timeline chart" do
    get rails_pulse.request_path(@request_record)

    assert_response :success
    operation_timeline = assigns(:operation_timeline)

    assert_instance_of RailsPulse::Charts::OperationsChart, operation_timeline
  end

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
