require "test_helper"

class ResponseRangeConcernTest < ActionController::TestCase
  class TestController < ActionController::Base
    include ResponseRangeConcern

    attr_accessor :params, :session

    def initialize
      super
      @params = ActionController::Parameters.new({})
      @session = {}
    end

    def session_global_filters
      @session[:global_filters] || {}
    end
  end

  setup do
    @controller = TestController.new
  end

  # Structure Tests

  test "setup_duration_range returns array with 2 elements" do
    result = @controller.send(:setup_duration_range, :route)

    assert_kind_of Array, result
    assert_equal 2, result.length
  end

  test "setup_duration_range returns integer for start_duration" do
    result = @controller.send(:setup_duration_range, :route)

    assert_kind_of Integer, result[0]
  end

  test "setup_duration_range returns symbol for selected_range" do
    result = @controller.send(:setup_duration_range, :route)

    assert_kind_of Symbol, result[1]
  end

  # Type-Specific Threshold Tests

  test "setup_duration_range uses route_thresholds for :route type" do
    @controller.params = ActionController::Parameters.new(q: { avg_duration: "slow" })

    start_duration, _selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:slow], start_duration
  end

  test "setup_duration_range uses request_thresholds for :request type" do
    @controller.params = ActionController::Parameters.new(q: { duration: "slow" })

    start_duration, _selected_range = @controller.send(:setup_duration_range, :request)

    assert_equal RailsPulse.configuration.request_thresholds[:slow], start_duration
  end

  test "setup_duration_range uses query_thresholds for :query type" do
    @controller.params = ActionController::Parameters.new(q: { avg_duration: "slow" })

    start_duration, _selected_range = @controller.send(:setup_duration_range, :query)

    assert_equal RailsPulse.configuration.query_thresholds[:slow], start_duration
  end

  test "setup_duration_range uses job_thresholds for :job type" do
    @controller.params = ActionController::Parameters.new(q: { avg_duration: "slow" })

    start_duration, _selected_range = @controller.send(:setup_duration_range, :job)

    assert_equal RailsPulse.configuration.job_thresholds[:slow], start_duration
  end

  # Priority 1: Page-Specific Duration Filter Tests

  test "setup_duration_range uses avg_duration param" do
    @controller.params = ActionController::Parameters.new(q: { avg_duration: "slow" })

    start_duration, selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:slow], start_duration
    assert_equal "slow", selected_range
  end

  test "setup_duration_range uses duration param" do
    @controller.params = ActionController::Parameters.new(q: { duration: "very_slow" })

    start_duration, selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:very_slow], start_duration
    assert_equal "very_slow", selected_range
  end

  test "setup_duration_range uses duration_gteq param" do
    @controller.params = ActionController::Parameters.new(q: { duration_gteq: "critical" })

    start_duration, selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:critical], start_duration
    assert_equal "critical", selected_range
  end

  test "setup_duration_range converts slow symbol to threshold value" do
    @controller.params = ActionController::Parameters.new(q: { avg_duration: :slow })

    start_duration, _selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:slow], start_duration
  end

  test "setup_duration_range converts very_slow symbol to threshold value" do
    @controller.params = ActionController::Parameters.new(q: { avg_duration: :very_slow })

    start_duration, _selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:very_slow], start_duration
  end

  test "setup_duration_range converts critical symbol to threshold value" do
    @controller.params = ActionController::Parameters.new(q: { avg_duration: :critical })

    start_duration, _selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:critical], start_duration
  end

  test "setup_duration_range defaults to 0 for unknown threshold" do
    @controller.params = ActionController::Parameters.new(q: { avg_duration: "unknown" })

    start_duration, selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal 0, start_duration
    assert_equal "unknown", selected_range
  end

  test "setup_duration_range prioritizes avg_duration over duration" do
    @controller.params = ActionController::Parameters.new(q: { avg_duration: "slow", duration: "critical" })

    start_duration, selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:slow], start_duration
    assert_equal "slow", selected_range
  end

  test "setup_duration_range prioritizes duration over duration_gteq" do
    @controller.params = ActionController::Parameters.new(q: { duration: "slow", duration_gteq: "critical" })

    start_duration, selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:slow], start_duration
    assert_equal "slow", selected_range
  end

  # Priority 2: Global Performance Threshold Tests

  test "setup_duration_range uses global performance_threshold from session" do
    @controller.session[:global_filters] = { "performance_threshold" => "slow" }

    start_duration, selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:slow], start_duration
    assert_equal :slow, selected_range
  end

  test "setup_duration_range converts global threshold to numeric value" do
    @controller.session[:global_filters] = { "performance_threshold" => "very_slow" }

    start_duration, _selected_range = @controller.send(:setup_duration_range, :query)

    assert_equal RailsPulse.configuration.query_thresholds[:very_slow], start_duration
  end

  test "setup_duration_range ignores global when page-specific present" do
    @controller.params = ActionController::Parameters.new(q: { avg_duration: "critical" })
    @controller.session[:global_filters] = { "performance_threshold" => "slow" }

    start_duration, selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal RailsPulse.configuration.route_thresholds[:critical], start_duration
    assert_equal "critical", selected_range
  end

  # Priority 3: No Filter Tests

  test "setup_duration_range returns 0 and :all when no filters" do
    start_duration, selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal 0, start_duration
    assert_equal :all, selected_range
  end

  test "setup_duration_range returns :all symbol for selected_range by default" do
    _start_duration, selected_range = @controller.send(:setup_duration_range, :route)

    assert_equal :all, selected_range
  end
end
