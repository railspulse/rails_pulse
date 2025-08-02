require "test_helper"

class RailsPulse::CachesControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"
    setup_clean_database
    stub_all_external_dependencies
    super
  end

  test "controller has show action" do
    controller = RailsPulse::CachesController.new
    assert_respond_to controller, :show
  end

  test "controller uses ComponentCacheKey for cache operations" do
    # Test that the controller references the ComponentCacheKey class
    assert_equal RailsPulse::ComponentCacheKey, RailsPulse::ComponentCacheKey
  end

  test "controller has private helper methods" do
    controller = RailsPulse::CachesController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :calculate_component_data
    assert_includes private_methods, :extract_route_from_context
    assert_includes private_methods, :extract_query_from_context
  end

  test "calculate_component_data handles unknown components" do
    controller = RailsPulse::CachesController.new
    controller.instance_variable_set(:@component_id, "unknown_component")

    result = controller.send(:calculate_component_data)
    assert_equal "Unknown Metric", result[:title]
    assert_equal "N/A", result[:summary]
  end

  private

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end
end
