require "test_helper"

class RailsPulse::RequestsControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"


    super
  end

  test "controller has index and show actions" do
    controller = RailsPulse::RequestsController.new

    assert_respond_to controller, :index
    assert_respond_to controller, :show
  end

  test "controller includes ChartTableConcern" do
    assert_includes RailsPulse::RequestsController.included_modules, ChartTableConcern
  end

  test "controller has required private methods" do
    controller = RailsPulse::RequestsController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :chart_model
    assert_includes private_methods, :table_model
    assert_includes private_methods, :chart_class
    assert_includes private_methods, :set_request
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

    assert_empty(options)
  end

  test "default table sort is by occurred_at descending" do
    controller = RailsPulse::RequestsController.new

    assert_equal "occurred_at desc", controller.send(:default_table_sort)
  end

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::RequestsController, :<, RailsPulse::ApplicationController
  end

  private

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end
end
