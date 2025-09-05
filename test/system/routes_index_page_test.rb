require "test_helper"
require_relative "../support/shared_index_page_test"

class RoutesIndexPageTest < SharedIndexPageTest
  def page_path
    "/routes"
  end

  def page_type
    :routes
  end

  def chart_selector
    "#average_response_times_chart"
  end

  def performance_filter_options
    {
      slow: "Slow (≥ 500ms)",
      critical: "Critical (≥ 3000ms)"
    }
  end

  def all_test_data
    (@fast_routes || []) + (@slow_routes || []) + (@very_slow_routes || []) + (@critical_routes || []) +
    [ @last_week_only_route, @last_month_only_route, @old_route ].compact
  end

  def default_scope_data
    (@fast_routes + @slow_routes + @very_slow_routes + @critical_routes)
  end

  def last_week_data
    default_scope_data + [ @last_week_only_route ]
  end

  def last_month_data
    default_scope_data + [ @last_week_only_route, @last_month_only_route ]
  end

  def slow_performance_data
    (@slow_routes + @very_slow_routes + @critical_routes + [ @last_week_only_route ]).compact
  end

  def critical_performance_data
    @critical_routes
  end

  def zoomed_data
    (@fast_routes + @slow_routes + @critical_routes)
  end

  def metric_card_selectors
    {
      "#average_response_times" => {
        title_regex: /AVERAGE RESPONSE TIME/,
        title_message: "Average response time card should have correct title",
        value_regex: /\d+(\.\d+)?\s*ms/,
        value_message: "Average response time should show ms value"
      },
      "#percentile_response_times" => {
        title_regex: /95TH PERCENTILE RESPONSE TIME/,
        title_message: "95th percentile card should have correct title",
        value_regex: /\d+(\.\d+)?\s*ms/,
        value_message: "95th percentile should show ms value"
      },
      "#request_count_totals" => {
        title_regex: /REQUEST COUNT TOTAL/,
        title_message: "Request count card should have correct title",
        value_regex: /\d+\s*\/\s*min/,
        value_message: "Request count should show per minute value"
      },
      "#error_rate_per_route" => {
        title_regex: /ERROR RATE PER ROUTE/,
        title_message: "Error rate card should have correct title",
        value_regex: /\d+(\.\d+)?%/,
        value_message: "Error rate should show percentage value"
      }
    }
  end

  def sortable_columns
    [
      {
        name: "Average Response Time",
        index: 2,
        value_extractor: ->(text) { text.gsub(/[^\d.]/, "").to_f }
      },
      {
        name: "Route",
        index: 1,
        value_extractor: ->(text) { text.strip }
      }
    ]
  end

  def additional_filter_test
    fill_in "q[route_path_cont]", with: "api"
  end

  # Routes-specific test that doesn't fit the common pattern
  def test_route_path_filter_works_correctly
    visit_rails_pulse_path "/routes"

    # Test filtering by "api" should show API routes
    fill_in "q[route_path_cont]", with: "api"
    click_button "Search"

    # Validate filtered results contain only API routes
    api_routes = all_test_data.select { |r| r.path.include?("api") }
    validate_chart_data("#average_response_times_chart", expected_data: api_routes, filter_applied: "API routes")
    validate_table_data(page_type: :routes, filter_applied: "api")

    # Test filtering by "admin" should show admin routes
    fill_in "q[route_path_cont]", with: "admin"
    click_button "Search"

    # Validate filtered results contain only admin routes
    admin_routes = all_test_data.select { |r| r.path.include?("admin") }
    validate_chart_data("#average_response_times_chart", expected_data: admin_routes, filter_applied: "Admin routes")
    validate_table_data(page_type: :routes, filter_applied: "admin")
  end

  # Test additional sortable columns specific to routes
  def test_additional_sortable_columns_work
    visit_rails_pulse_path "/routes"

    # Wait for table to load
    assert_selector "table tbody tr", wait: 5

    # Test Requests column sorting
    within("table thead") do
      click_link "Requests"
    end
    assert_selector "table tbody tr", wait: 3

    # Test Error Rate column sorting
    within("table thead") do
      click_link "Error Rate (%)"
    end
    assert_selector "table tbody tr", wait: 3
  end

  def test_average_response_time_sorting_fails
    visit_rails_pulse_path "/routes"

    # Wait for table to load
    assert_selector "table tbody tr", wait: 5

    # Get initial order of rows
    initial_rows = all("table tbody tr").map(&:text)

    # Click on Average Response Time header
    within("table thead") do
      click_link "Average Response Time"
    end

    # Wait and get new order of rows
    sleep 1
    sorted_rows = all("table tbody tr").map(&:text)

    # Assert that clicking the header actually changed the order
    refute_equal initial_rows, sorted_rows, "Expected row order to change when clicking Average Response Time header, but it remained the same"
  end

  def test_empty_state_displays_when_no_data_matches_filters
    # Clear all data to ensure empty state
    RailsPulse::Summary.destroy_all
    RailsPulse::Request.destroy_all
    RailsPulse::Route.destroy_all

    visit_rails_pulse_path "/routes"

    # Should show empty state when no data exists
    assert_text "No route data found for the selected filters."
    assert_text "Try adjusting your time range or filters to see results."
    
    # Check for the search.svg image in the empty state
    assert_selector "img[src*='search.svg']"
    
    # Should not show chart or table
    assert_no_selector "#average_response_times_chart"
    assert_no_selector "table tbody tr"
  end

  private

  def create_comprehensive_test_data
    # Create routes with predictable performance characteristics
    create_performance_categorized_routes

    # Create requests with specific performance patterns
    create_performance_categorized_requests

    # Generate queries using existing bulk data helper
    create_query_data

    # Create Summary data needed for routes index page
    create_summary_data_for_routes
  end

  def create_performance_categorized_routes
    # Create routes for each performance threshold with distinctive paths
    @fast_routes = [
      create(:route, :fast_endpoint, path: "/api/health", method: "GET"),
      create(:route, :fast_endpoint, path: "/api/status", method: "GET"),
      create(:route, :fast_endpoint, path: "/api/ping", method: "POST")
    ]

    @slow_routes = [
      create(:route, :slow_endpoint, path: "/api/users", method: "GET"),
      create(:route, :slow_endpoint, path: "/api/orders", method: "POST")
    ]

    @very_slow_routes = [
      create(:route, :very_slow_endpoint, path: "/api/reports", method: "GET"),
      create(:route, :very_slow_endpoint, path: "/admin/analytics", method: "GET")
    ]

    @critical_routes = [
      create(:route, :critical_endpoint, path: "/admin/heavy_import", method: "POST")
    ]

    # Create time-specific routes to test filtering
    @last_week_only_route = create(:route, :slow_endpoint, path: "/api/last_week_feature", method: "GET")
    @last_month_only_route = create(:route, :fast_endpoint, path: "/api/last_month_feature", method: "GET")
    @old_route = create(:route, :very_slow_endpoint, path: "/api/old_feature", method: "GET")
  end

  def create_performance_categorized_requests
    # Create requests with known performance characteristics aligned with thresholds
    # To test zoom functionality properly, we'll create different routes active at different times

    # Fast routes: Only active in recent period (recent hour activity)
    @fast_routes.each do |route|
      create_requests_for_route(route, avg_duration: 200, count: 20, time_spread: :recent)
    end

    # Slow routes: Active in both recent and last week (will appear in both zoom and full view)
    @slow_routes.each do |route|
      create_requests_for_route(route, avg_duration: 800, count: 15, time_spread: :recent)
      create_requests_for_route(route, avg_duration: 750, count: 10, time_spread: :last_week)
    end

    # Very slow routes: Only active in last week period (won't appear in recent zoom)
    @very_slow_routes.each do |route|
      create_requests_for_route(route, avg_duration: 1800, count: 8, time_spread: :last_week)
    end

    # Critical routes: Only active in recent period (will appear in zoom)
    @critical_routes.each do |route|
      create_requests_for_route(route, avg_duration: 4000, count: 5, time_spread: :recent)
    end

    # Time-specific routes for testing filtering boundaries
    create_requests_for_route(@last_week_only_route, avg_duration: 800, count: 5, time_spread: :last_week_only)
    create_requests_for_route(@last_month_only_route, avg_duration: 300, count: 8, time_spread: :last_month_only)
    create_requests_for_route(@old_route, avg_duration: 2000, count: 3, time_spread: :old)
  end

  def create_requests_for_route(route, avg_duration:, count:, time_spread:)
    base_time = case time_spread
    when :recent then 2.hours.ago
    when :last_week then 10.days.ago
    when :last_week_only then 6.days.ago
    when :last_month_only then 20.days.ago
    when :old then 40.days.ago
    else 3.days.ago
    end

    count.times do |i|
      duration_variation = (avg_duration * 0.4 * rand) - (avg_duration * 0.2)
      actual_duration = [ 1, avg_duration + duration_variation ].max.round

      create(:request,
        route: route,
        duration: actual_duration,
        occurred_at: base_time + (i * 10).minutes,
        status: rand(10) == 0 ? 500 : 200,
        is_error: rand(10) == 0
      )
    end
  end

  def create_query_data
    @queries = 3.times.map { create(:query, :realistic_sql) }
  end

  def create_summary_data_for_routes
    time_spreads = {
      recent: 2.hours.ago,
      last_week: 10.days.ago,
      last_week_only: 6.days.ago,
      last_month_only: 20.days.ago,
      old: 40.days.ago
    }

    time_spreads.each do |spread_type, base_time|
      service = RailsPulse::SummaryService.new("day", base_time.beginning_of_day)
      service.perform

      if spread_type == :recent
        service = RailsPulse::SummaryService.new("hour", base_time.beginning_of_hour)
        service.perform
      end
    end

    service = RailsPulse::SummaryService.new("day", Time.current.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("hour", Time.current.beginning_of_hour)
    service.perform
  end
end
