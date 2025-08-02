require "test_helper"

class RailsPulse::RoutesControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"
    setup_clean_database
    stub_all_external_dependencies
    super
  end

  test "controller has index and show actions" do
    controller = RailsPulse::RoutesController.new
    assert_respond_to controller, :index
    assert_respond_to controller, :show
  end

  test "controller includes ChartTableConcern" do
    assert RailsPulse::RoutesController.included_modules.include?(ChartTableConcern)
  end

  test "controller has required private methods" do
    controller = RailsPulse::RoutesController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :chart_model
    assert_includes private_methods, :table_model
    assert_includes private_methods, :chart_class
    assert_includes private_methods, :set_route
    assert_includes private_methods, :show_action?
  end

  test "uses correct chart class" do
    controller = RailsPulse::RoutesController.new
    assert_equal RailsPulse::Routes::Charts::AverageResponseTimes, controller.send(:chart_class)
  end

  test "show_action method works correctly" do
    controller = RailsPulse::RoutesController.new

    # Mock action_name for index
    controller.stubs(:action_name).returns("index")
    refute controller.send(:show_action?)

    # Mock action_name for show
    controller.stubs(:action_name).returns("show")
    assert controller.send(:show_action?)
  end

  test "determines correct duration field for index vs show" do
    controller = RailsPulse::RoutesController.new

    # Mock for index action
    controller.stubs(:action_name).returns("index")
    assert_equal :requests_duration_gteq, controller.send(:duration_field)

    # Mock for show action
    controller.stubs(:action_name).returns("show")
    assert_equal :duration_gteq, controller.send(:duration_field)
  end

  test "uses correct models based on action" do
    controller = RailsPulse::RoutesController.new

    # For index action - uses Route model
    controller.stubs(:action_name).returns("index")
    assert_equal RailsPulse::Route, controller.send(:chart_model)
    assert_equal RailsPulse::Route, controller.send(:table_model)

    # For show action - uses Request model
    controller.stubs(:action_name).returns("show")
    assert_equal RailsPulse::Request, controller.send(:chart_model)
    assert_equal RailsPulse::Request, controller.send(:table_model)
  end

  test "controller inherits from ApplicationController" do
    assert RailsPulse::RoutesController < RailsPulse::ApplicationController
  end

  private

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end
end
