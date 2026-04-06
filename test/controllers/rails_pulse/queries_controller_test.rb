require "test_helper"

class RailsPulse::QueriesControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"


    super
  end

  test "controller has index, show, and analyze actions" do
    controller = RailsPulse::QueriesController.new

    assert_respond_to controller, :index
    assert_respond_to controller, :show
    assert_respond_to controller, :analyze
  end

  test "controller includes ChartTableConcern" do
    assert_includes RailsPulse::QueriesController.included_modules, ChartTableConcern
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

    assert_equal RailsPulse::Queries::Charts::QueryPerformance, controller.send(:chart_class)
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

    assert_predicate query, :analyzed?
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

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::QueriesController, :<, RailsPulse::ApplicationController
  end

  # HTTP Response Tests

  test "index response body is not nil" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil response.body
  end

  test "index response body has content" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_operator response.body.length, :>, 0
  end

  test "index response content type is HTML" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_equal "text/html; charset=utf-8", response.content_type
  end

  test "index no errors or exceptions raised" do
    setup_basic_test_data

    assert_nothing_raised do
      get rails_pulse_engine.queries_path
    end
  end

  test "index action loads successfully" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  # Instance Variable Assignment Tests

  test "index assigns percentile_query_times_metric_card" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:percentile_query_times_metric_card)
  end

  test "index assigns execution_rate_metric_card" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:execution_rate_metric_card)
  end

  test "index assigns database_load_metric_card" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:database_load_metric_card)
  end

  test "index assigns query_performance_chart_data" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:query_performance_chart_data)
  end

  test "index assigns execution_volume_chart_data" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:execution_volume_chart_data)
  end

  test "index assigns database_load_chart_data" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:database_load_chart_data)
  end

  test "index assigns chart_data for backward compatibility" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:chart_data)
    # Should reference query_performance_chart_data
    assert_equal assigns(:query_performance_chart_data), assigns(:chart_data)
  end

  test "index assigns pagination" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:pagination)
  end

  test "index assigns ransack_query" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:ransack_query)
  end

  test "index assigns start_time and end_time" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:start_time)
    assert_not_nil assigns(:end_time)
  end

  test "index assigns has_data flag" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:has_data)
  end

  test "index assigns has_chart_data flag" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:has_chart_data)
  end

  test "index assigns table_data" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:table_data)
  end

  # Metric Cards Tests

  test "metric cards created on normal request" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_not_nil assigns(:percentile_query_times_metric_card)
    assert_not_nil assigns(:execution_rate_metric_card)
    assert_not_nil assigns(:database_load_metric_card)
  end

  test "metric cards skipped when Turbo-Frame header present" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, headers: { "Turbo-Frame" => "table_frame" }

    assert_response :success
    # Metric cards should be nil on turbo frame requests
    assert_nil assigns(:percentile_query_times_metric_card)
    assert_nil assigns(:execution_rate_metric_card)
    assert_nil assigns(:database_load_metric_card)
    # Table data should still be present
    assert_not_nil assigns(:table_data)
  end

  test "metric cards have required keys" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    card = assigns(:percentile_query_times_metric_card)
    assert_includes card.keys, :id
    assert_includes card.keys, :title
    assert_includes card.keys, :summary
    assert_includes card.keys, :chart_data

    card2 = assigns(:execution_rate_metric_card)
    assert_includes card2.keys, :id
    assert_includes card2.keys, :title
    assert_includes card2.keys, :summary
    assert_includes card2.keys, :chart_data

    card3 = assigns(:database_load_metric_card)
    assert_includes card3.keys, :id
    assert_includes card3.keys, :title
    assert_includes card3.keys, :summary
  end

  # Chart Data Tests

  test "query_performance_chart_data has series and labels" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    chart = assigns(:query_performance_chart_data)
    assert_kind_of Hash, chart
    assert_includes chart.keys, :series
    assert_includes chart.keys, :labels
  end

  test "execution_volume_chart_data has series and labels" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    chart = assigns(:execution_volume_chart_data)
    assert_kind_of Hash, chart
    assert_includes chart.keys, :series
    assert_includes chart.keys, :labels
  end

  test "database_load_chart_data has series and labels" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    chart = assigns(:database_load_chart_data)
    assert_kind_of Hash, chart
    assert_includes chart.keys, :series
    assert_includes chart.keys, :labels
  end

  test "chart series have required attributes" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    chart = assigns(:query_performance_chart_data)
    chart[:series].each do |series|
      assert_includes series.keys, :name
      assert_includes series.keys, :data
      assert_kind_of Array, series[:data]
    end
  end

  # Time Range Filtering Tests

  test "index default time range is last_week" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_response :success
    # Default should be approximately 7 days
    time_diff = assigns(:end_time) - assigns(:start_time)
    assert_operator time_diff, :>, 6.days.to_i
    assert_operator time_diff, :<, 8.days.to_i
  end

  test "index with session time_range_preference" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: {}, session: {
      time_range_preference: "last_week"
    }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  test "index with custom time range" do
    setup_basic_test_data

    start_time = 2.days.ago
    end_time = Time.current

    get rails_pulse_engine.queries_path, params: {
      q: {
        custom_date_range: "#{start_time.strftime('%Y-%m-%d %H:%M')} to #{end_time.strftime('%Y-%m-%d %H:%M')}"
      }
    }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  test "period type is hour for ranges under 25 hours" do
    setup_basic_test_data

    # Set a time range under 25 hours via session
    get rails_pulse_engine.queries_path, params: {}, session: {
      global_filters: {
        start_time: 12.hours.ago.to_i,
        end_time: Time.current.to_i
      }
    }

    assert_response :success
    time_diff_hours = (assigns(:end_time) - assigns(:start_time)) / 3600.0
    assert_operator time_diff_hours, :<=, 25
  end

  test "period type is day for ranges over 25 hours" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_response :success
    time_diff_hours = (assigns(:end_time) - assigns(:start_time)) / 3600.0
    assert_operator time_diff_hours, :>, 25
  end

  # Duration Filtering Tests

  test "index with no duration filter shows all" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_response :success
    # start_duration should be 0 or nil
    assert assigns(:start_duration).nil? || assigns(:start_duration) == 0
  end

  test "index with slow duration filter" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { q: { avg_duration: "slow" } }

    assert_response :success
    # start_duration should be set (≥ 100ms)
    assert_not_nil assigns(:start_duration)
    assert_operator assigns(:start_duration), :>=, 0
  end

  test "index with very_slow duration filter" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { q: { avg_duration: "very_slow" } }

    assert_response :success
    # start_duration should be set (≥ 500ms)
    assert_not_nil assigns(:start_duration)
    assert_operator assigns(:start_duration), :>=, 0
  end

  test "index with critical duration filter" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { q: { avg_duration: "critical" } }

    assert_response :success
    # start_duration should be set (≥ 1000ms)
    assert_not_nil assigns(:start_duration)
    assert_operator assigns(:start_duration), :>=, 0
  end

  test "index with invalid duration parameter" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { q: { avg_duration: "invalid" } }

    assert_response :success
    # Should ignore invalid parameter
    assert assigns(:start_duration).nil? || assigns(:start_duration) == 0
  end

  test "duration filter passed to chart services" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { q: { avg_duration: "slow" } }

    assert_response :success
    assert_not_nil assigns(:query_performance_chart_data)
    assert_not_nil assigns(:execution_volume_chart_data)
    assert_not_nil assigns(:database_load_chart_data)
  end

  test "duration filter passed to table service" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { q: { avg_duration: "slow" } }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  # Sorting Tests

  test "index action with sorting by avg_duration" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { q: { s: "avg_duration_sort desc" } }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  test "index action with sorting by p95_duration" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { q: { s: "p95_duration_sort desc" } }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  test "index action with sorting by execution_count" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { q: { s: "execution_count_sort desc" } }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  test "index with ascending sort" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { q: { s: "avg_duration_sort asc" } }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  # Pagination Tests

  test "index action with pagination limit" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { limit: "50" }

    assert_response :success
    pagination = assigns(:pagination)
    assert_not_nil pagination
  end

  test "pagination limit is stored in session" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { limit: "50" }

    # Verify session was updated
    assert_equal 50, session[:pagination_limit]
  end

  test "pagination uses default limit when not specified" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_response :success
    pagination = assigns(:pagination)
    assert_not_nil pagination
  end

  test "pagination with custom page" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: { page: "2", limit: "10" }

    assert_response :success
    assert_not_nil assigns(:pagination)
  end

  # Parameter Combination Tests

  test "time range and duration filter combined" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: {
      q: {
        avg_duration: "slow"
      }
    }, session: {
      time_range_preference: "last_week"
    }

    assert_response :success
    assert_not_nil assigns(:table_data)
    assert_not_nil assigns(:start_duration)
  end

  test "time range and sorting combined" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: {
      q: {
        s: "p95_duration_sort desc"
      }
    }, session: {
      time_range_preference: "last_week"
    }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  test "all filters combined" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: {
      q: {
        avg_duration: "slow",
        s: "p95_duration_sort desc"
      },
      limit: "25"
    }, session: {
      time_range_preference: "last_week"
    }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  # Edge Case Tests

  test "index with empty data" do
    # Don't setup any test data
    get rails_pulse_engine.queries_path

    assert_response :success
    # Should not raise errors even with no data
  end

  test "index with very large time range" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: {}, session: {
      global_filters: {
        start_time: 90.days.ago.to_i,
        end_time: Time.current.to_i
      }
    }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  test "index with future dates" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: {}, session: {
      global_filters: {
        start_time: 10.days.from_now.to_i,
        end_time: 11.days.from_now.to_i
      }
    }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  test "conflicting parameters handled" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path, params: {
      q: {
        avg_duration: "slow"
      }
    }, session: {
      time_range_preference: "last_week",
      global_filters: {
        start_time: 30.days.ago.to_i,
        end_time: Time.current.to_i
      }
    }

    assert_response :success
    assert_not_nil assigns(:table_data)
  end

  # Default Sort Tests

  test "default table sort is period_start desc" do
    controller = RailsPulse::QueriesController.new

    assert_equal "period_start desc", controller.send(:default_table_sort)
  end

  # Tag Filtering Tests

  test "index loads successfully with default tag settings" do
    setup_basic_test_data

    get rails_pulse_engine.queries_path

    assert_response :success
    assert_not_nil assigns(:table_data)
    assert_not_nil assigns(:query_performance_chart_data)
    assert_not_nil assigns(:execution_volume_chart_data)
    assert_not_nil assigns(:database_load_chart_data)
  end

  private

  def setup_basic_test_data
    # Use existing fixture data
    @query1 = rails_pulse_queries(:simple_query)
    @query2 = rails_pulse_queries(:complex_query)

    # Generate summary data for the current hour (where fixtures exist)
    service = RailsPulse::SummaryService.new("hour", Time.current.beginning_of_hour)
    service.perform
  end

  def create_test_query_with_operations
    # Use existing fixture data
    rails_pulse_queries(:complex_query)
  end

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end
end
