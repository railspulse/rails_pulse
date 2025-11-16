require "test_helper"

class RailsPulse::OperationsControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @request_operation = rails_pulse_operations(:sql_operation_1)
    @job_run_operation = rails_pulse_operations(:job_sql_operation)
  end

  # Controller Structure Tests

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
    assert_includes private_methods, :calculate_percentile
  end

  test "controller has all optimization suggestion methods" do
    controller = RailsPulse::OperationsController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :sql_optimization_suggestions
    assert_includes private_methods, :view_optimization_suggestions
    assert_includes private_methods, :controller_optimization_suggestions
    assert_includes private_methods, :cache_optimization_suggestions
    assert_includes private_methods, :http_optimization_suggestions
  end

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::OperationsController, :<, RailsPulse::ApplicationController
  end

  # Show Action Tests - Request Operations

  test "show action loads successfully for request operation" do
    get rails_pulse.operation_path(@request_operation)

    assert_response :success
    assert_not_nil assigns(:operation)
    assert_not_nil assigns(:request)
    assert_not_nil assigns(:parent)
    assert_not_nil assigns(:related_operations)
    assert_not_nil assigns(:performance_context)
    assert_not_nil assigns(:optimization_suggestions)
    assert_equal @request_operation, assigns(:operation)
    assert_equal @request_operation.request, assigns(:request)
  end

  test "show action sets parent to request for request operation" do
    get rails_pulse.operation_path(@request_operation)

    assert_response :success
    assert_equal @request_operation.request, assigns(:parent)
    assert_nil assigns(:job_run)
  end

  # Show Action Tests - Job Run Operations

  test "show action loads successfully for job run operation" do
    get rails_pulse.operation_path(@job_run_operation)

    assert_response :success
    assert_not_nil assigns(:operation)
    assert_not_nil assigns(:job_run)
    assert_not_nil assigns(:parent)
    assert_not_nil assigns(:related_operations)
    assert_not_nil assigns(:performance_context)
    assert_not_nil assigns(:optimization_suggestions)
    assert_equal @job_run_operation, assigns(:operation)
    assert_equal @job_run_operation.job_run, assigns(:job_run)
  end

  test "show action sets parent to job_run for job run operation" do
    get rails_pulse.operation_path(@job_run_operation)

    assert_response :success
    assert_equal @job_run_operation.job_run, assigns(:parent)
    assert_nil assigns(:request)
  end

  # Related Operations Tests

  test "show action finds related operations" do
    get rails_pulse.operation_path(@request_operation)

    assert_response :success
    related = assigns(:related_operations)

    # Should be an ActiveRecord relation or array
    assert_respond_to related, :each
    # Should not include the current operation
    refute_includes related.map(&:id), @request_operation.id
  end

  # Performance Context Tests

  test "show action calculates performance context" do
    get rails_pulse.operation_path(@request_operation)

    assert_response :success
    context = assigns(:performance_context)

    assert_kind_of Hash, context
    # Should have percentile keys
    if context.any?
      assert context.key?(:percentile_50) || context.key?(:average)
    end
  end

  # Optimization Suggestions Tests

  test "show action generates optimization suggestions" do
    get rails_pulse.operation_path(@request_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)

    assert_kind_of Array, suggestions
  end

  # Private Method Tests

  test "calculates percentile correctly" do
    controller = RailsPulse::OperationsController.new

    # Test percentile calculation with known values
    sorted_array = [ 10, 20, 30, 40, 50 ]

    # 25 should be at 40th percentile (between 20 and 30)
    percentile = controller.send(:calculate_percentile, 25, sorted_array)

    assert_in_delta 40.0, percentile, 0.1

    # 35 should be at 60th percentile
    percentile = controller.send(:calculate_percentile, 35, sorted_array)

    assert_in_delta 60.0, percentile, 0.1

    # Test edge cases
    assert_equal 0, controller.send(:calculate_percentile, 5, sorted_array)
    assert_in_delta(100.0, controller.send(:calculate_percentile, 100, sorted_array))
  end

  test "calculates percentile for empty array" do
    controller = RailsPulse::OperationsController.new

    percentile = controller.send(:calculate_percentile, 50, [])

    assert_equal 0, percentile
  end

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
