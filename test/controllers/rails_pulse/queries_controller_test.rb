require "test_helper"

class RailsPulse::QueriesControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"
    setup_clean_database
    stub_all_external_dependencies
    super
  end

  test "controller has index, show, and analyze actions" do
    controller = RailsPulse::QueriesController.new
    assert_respond_to controller, :index
    assert_respond_to controller, :show
    assert_respond_to controller, :analyze
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

  test "show_action method works correctly" do
    controller = RailsPulse::QueriesController.new

    # Mock action_name for index
    controller.stubs(:action_name).returns("index")
    refute controller.send(:show_action?)

    # Mock action_name for show
    controller.stubs(:action_name).returns("show")
    assert controller.send(:show_action?)
  end

  test "analyze action performs query analysis and responds appropriately" do
    query = create_test_query_with_operations

    # Test successful analysis with HTML format
    post rails_pulse_engine.analyze_query_path(query)
    assert_redirected_to rails_pulse_engine.query_path(query)
    assert_equal "Query analysis completed successfully.", flash[:notice]

    # Verify analysis was saved
    query.reload
    assert query.analyzed?
    assert_not_nil query.query_stats
  end

  test "analyze action handles errors gracefully" do
    query = create_test_query_with_operations

    # Stub the service to raise an error
    RailsPulse::QueryAnalysisService.stubs(:analyze_query).raises(StandardError.new("Test error"))

    post rails_pulse_engine.analyze_query_path(query)
    assert_redirected_to rails_pulse_engine.query_path(query)
    assert_equal "Query analysis failed: Test error", flash[:alert]
  end

  private

  def create_test_query_with_operations
    query = RailsPulse::Query.create!(normalized_sql: "SELECT * FROM users WHERE id = ?")

    route = RailsPulse::Route.create!(method: "GET", path: "/users")
    request = RailsPulse::Request.create!(
      route: route,
      duration: 100.0,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid,
      occurred_at: 1.hour.ago
    )

    RailsPulse::Operation.create!(
      request: request,
      query: query,
      operation_type: "sql",
      label: query.normalized_sql,
      duration: 50.0,
      start_time: 0.0,
      occurred_at: 1.hour.ago
    )

    query
  end

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end
end
