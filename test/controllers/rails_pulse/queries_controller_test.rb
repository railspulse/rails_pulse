require "test_helper"

class RailsPulse::QueriesControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"
    setup_clean_database
    stub_all_external_dependencies
    super
  end

  test "controller has index and show actions" do
    controller = RailsPulse::QueriesController.new
    assert_respond_to controller, :index
    assert_respond_to controller, :show
  end

  test "controller includes ChartTableConcern" do
    assert RailsPulse::QueriesController.included_modules.include?(ChartTableConcern)
  end

  test "controller has required private methods" do
    controller = RailsPulse::QueriesController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :chart_model
    assert_includes private_methods, :table_model
    assert_includes private_methods, :chart_class
    assert_includes private_methods, :set_query
  end

  test "uses correct chart class" do
    controller = RailsPulse::QueriesController.new
    assert_equal RailsPulse::Queries::Charts::AverageQueryTimes, controller.send(:chart_class)
  end

  test "uses correct default table sort" do
    controller = RailsPulse::QueriesController.new
    assert_equal "occurred_at desc", controller.send(:default_table_sort)
  end

  test "optimized aggregations include required fields" do
    controller = RailsPulse::QueriesController.new
    sql = controller.send(:optimized_aggregations_sql)

    assert_includes sql, "AVG(rails_pulse_operations.duration)"
    assert_includes sql, "COUNT(rails_pulse_operations.id)"
    assert_includes sql, "SUM(rails_pulse_operations.duration)"
    assert_includes sql, "MAX(rails_pulse_operations.occurred_at)"
  end

  test "show_action method works correctly" do
    controller = RailsPulse::QueriesController.new

    # Mock action_name for index
    controller.stubs(:action_name).returns("index")
    refute controller.send(:show_action?)

    # Mock action_name for show
    controller.stubs(:action_name).returns("show")
    assert controller.send(:show_action?)
  end

  private

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end
end
