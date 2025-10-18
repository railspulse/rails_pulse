require "test_helper"

class RailsPulse::OperationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"
    super
  end

  test "controller has show action" do
    controller = RailsPulse::OperationsController.new

    assert_respond_to controller, :show
  end

  test "controller has required private methods" do
    controller = RailsPulse::OperationsController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :set_operation
    assert_includes private_methods, :find_related_operations
    assert_includes private_methods, :calculate_performance_context
    assert_includes private_methods, :generate_optimization_suggestions
  end

  test "controller has optimization suggestion methods" do
    controller = RailsPulse::OperationsController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :sql_optimization_suggestions
    assert_includes private_methods, :view_optimization_suggestions
    assert_includes private_methods, :controller_optimization_suggestions
  end

  test "calculates percentile correctly" do
    controller = RailsPulse::OperationsController.new

    # Test percentile calculation with known values
    sorted_array = [ 10, 20, 30, 40, 50 ]

    # 25 should be at 40th percentile (between 20 and 30)
    percentile = controller.send(:calculate_percentile, 25, sorted_array)

    assert_in_delta(40.0, percentile)

    # 35 should be at 60th percentile
    percentile = controller.send(:calculate_percentile, 35, sorted_array)

    assert_in_delta(60.0, percentile)
  end

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::OperationsController, :<, RailsPulse::ApplicationController
  end

  private

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end
end
