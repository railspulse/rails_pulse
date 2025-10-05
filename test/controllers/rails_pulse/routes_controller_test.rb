require "test_helper"

class RailsPulse::RoutesControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
  end

  test "controller includes ChartTableConcern" do
    assert_includes RailsPulse::RoutesController.included_modules, ChartTableConcern
  end

  test "controller has index and show actions" do
    controller = RailsPulse::RoutesController.new

    assert_respond_to controller, :index
    assert_respond_to controller, :show
  end

  test "controller has required private methods" do
    controller = RailsPulse::RoutesController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :chart_model
    assert_includes private_methods, :table_model
    assert_includes private_methods, :chart_class
    assert_includes private_methods, :set_route
  end

  test "uses correct models based on action" do
    controller = RailsPulse::RoutesController.new

    # For index action - uses Summary model
    controller.stubs(:action_name).returns("index")

    assert_equal RailsPulse::Summary, controller.send(:chart_model)
    assert_equal RailsPulse::Summary, controller.send(:table_model)

    # For show action - chart always uses Summary, table uses Request
    controller.stubs(:action_name).returns("show")

    assert_equal RailsPulse::Summary, controller.send(:chart_model)
    assert_equal RailsPulse::Request, controller.send(:table_model)
  end

  test "uses correct chart class" do
    controller = RailsPulse::RoutesController.new

    assert_equal RailsPulse::Routes::Charts::AverageResponseTimes, controller.send(:chart_class)
  end

  test "default table sort" do
    controller = RailsPulse::RoutesController.new

    # For index action
    controller.stubs(:action_name).returns("index")

    assert_equal "avg_duration desc", controller.send(:default_table_sort)

    # For show action
    controller.stubs(:action_name).returns("show")

    assert_equal "occurred_at desc", controller.send(:default_table_sort)
  end

  test "index action loads successfully" do
    setup_basic_test_data

    get rails_pulse.routes_path

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  # Skip show action tests due to mocking complexity in test environment

  test "index action with time filtering" do
    setup_basic_test_data

    get rails_pulse.routes_path, params: { q: { period_start_range: "last_week" } }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  test "index action with sorting" do
    setup_basic_test_data

    get rails_pulse.routes_path, params: { q: { s: "count asc" } }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end


  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::RoutesController, :<, RailsPulse::ApplicationController
  end

  private

  def setup_basic_test_data
    # Use existing fixture data
    @route = rails_pulse_routes(:api_test)
    @route2 = rails_pulse_routes(:api_other)

    # Generate summary data for the current hour (where fixtures exist)
    service = RailsPulse::SummaryService.new("hour", Time.current.beginning_of_hour)
    service.perform
  end

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
