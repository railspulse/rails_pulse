require "test_helper"
require_relative "../support/chart_validation_helpers"

class DashboardIndexPageTest < ApplicationSystemTestCase
  include ChartValidationHelpers

  def setup
    super
    create_comprehensive_test_data
  end

  def test_dashboard_index_page_loads_and_displays_data
    visit_rails_pulse_path "/"

    # Verify basic page structure
    assert_selector "body"
    assert_current_path "/rails_pulse/"

    # Verify the essential elements of the dashboard
    assert_text "AVERAGE RESPONSE TIME"
    assert_text "95TH PERCENTILE RESPONSE TIME"  
    assert_text "REQUEST COUNT TOTAL"
    assert_text "ERROR RATE PER ROUTE"

    # Verify charts are displayed
    assert_selector "#dashboard_average_response_time_chart"
    assert_selector "#dashboard_p95_response_time_chart"

    # Verify table panels are displayed
    assert_text "SLOWEST ROUTES THIS WEEK"
    assert_text "SLOWEST QUERIES THIS WEEK"
  end

  def test_metric_cards_display_data_correctly
    visit_rails_pulse_path "/"

    # Wait for page to load
    assert_text "AVERAGE RESPONSE TIME", wait: 5

    # Test that all expected metric card titles and values are present
    assert_text "AVERAGE RESPONSE TIME"
    assert_match(/\d+\s*ms/, page.text, "Should show average response time in ms")

    assert_text "95TH PERCENTILE RESPONSE TIME"
    assert_match(/\d+\s*ms/, page.text, "Should show 95th percentile time in ms")

    assert_text "REQUEST COUNT TOTAL"
    assert_match(/\d+\s*\/\s*min/, page.text, "Should show request count per minute")

    assert_text "ERROR RATE PER ROUTE"
    assert_match(/\d+(\.\d+)?%/, page.text, "Should show error rate as percentage")
  end

  def test_average_response_time_chart_displays_correctly
    visit_rails_pulse_path "/"

    # Verify chart element exists
    assert_selector "#dashboard_average_response_time_chart", wait: 5

    # Validate chart data accuracy using helper method
    # We created fast (200ms), slow (800ms), and critical (4000ms) routes
    validate_dashboard_chart_data(
      "#dashboard_average_response_time_chart",
      expected_min_value: 200,
      expected_max_value: 5000,
      data_type: "response time"
    )
  end

  def test_query_performance_chart_displays_correctly
    visit_rails_pulse_path "/"

    # Verify chart element exists
    assert_selector "#dashboard_p95_response_time_chart", wait: 5

    # Validate chart data accuracy using helper method
    # We created fast queries (50ms), slow queries (200ms), and critical queries (1500ms)
    validate_dashboard_chart_data(
      "#dashboard_p95_response_time_chart",
      expected_min_value: 50,
      expected_max_value: 2000,
      data_type: "query time"
    )
  end

  def test_slowest_routes_panel_displays_data
    visit_rails_pulse_path "/"

    # Wait for panel to load
    assert_text "SLOWEST ROUTES THIS WEEK", wait: 5

    # Verify table structure within the slowest routes panel
    within_panel "SLOWEST ROUTES THIS WEEK" do
      assert_selector "table"
      assert_selector "table thead"
      assert_selector "table tbody tr", minimum: 1

      # Should show route information
      within "table tbody" do
        # Should have columns for route, method, avg time, requests
        assert_selector "tr:first-child td", count: 4

        # Verify we have our test data represented (should show admin heavy import route)
        assert_text "/admin/heavy_import"

        # Check that average time values are reasonable (in ms)
        first_row_avg_time = find("tr:first-child td:nth-child(2)").text
        assert_match(/\d+\s*ms/, first_row_avg_time, "Average time should show milliseconds")

        # Check that request count is shown
        first_row_requests = find("tr:first-child td:nth-child(3)").text
        assert_match(/\d+/, first_row_requests, "Request count should be numeric")
      end
    end
  end

  def test_slowest_queries_panel_displays_data
    visit_rails_pulse_path "/"

    # Wait for panel to load
    assert_text "SLOWEST QUERIES THIS WEEK", wait: 5

    # Verify table structure within the slowest queries panel
    within_panel "SLOWEST QUERIES THIS WEEK" do
      assert_selector "table"
      assert_selector "table thead"
      assert_selector "table tbody tr", minimum: 1

      # Should show query information
      within "table tbody" do
        # Should have columns for query, avg time, executions, last seen
        assert_selector "tr:first-child td", count: 4

        # Verify we have our test data represented (should show audit logs query as slowest)
        assert_text "audit_logs"

        # Check that average time values are reasonable (in ms)
        first_row_avg_time = find("tr:first-child td:nth-child(2)").text
        assert_match(/\d+\s*ms/, first_row_avg_time, "Average time should show milliseconds")

        # Check that execution count is shown
        first_row_executions = find("tr:first-child td:nth-child(3)").text
        assert_match(/\d+/, first_row_executions, "Execution count should be numeric")
      end
    end
  end

  private


  def within_panel(panel_title, &block)
    # Find the panel by its title and work within it
    # Try different title element types since it might not be h3
    panel_element = nil
    [ "h1", "h2", "h3", "h4", "h5", ".panel-title", "[class*='title']" ].each do |selector|
      begin
        panel_element = find(selector, text: panel_title, match: :first).ancestor(".grid-item")
        break
      rescue Capybara::ElementNotFound
        next
      end
    end

    # If not found by title element, try finding by text content
    if panel_element.nil?
      panel_element = find(".grid-item", text: /#{Regexp.escape(panel_title)}/i, match: :first)
    end

    within(panel_element, &block)
  end

  def create_comprehensive_test_data
    # Create routes with predictable performance characteristics
    create_performance_categorized_routes

    # Create queries with predictable performance characteristics
    create_performance_categorized_queries

    # Create requests with specific performance patterns
    create_performance_categorized_requests

    # Create operations for queries
    create_performance_categorized_operations

    # Create Summary data needed for dashboard
    create_summary_data_for_dashboard
  end

  def create_performance_categorized_routes
    @fast_routes = [
      create(:route, :fast_endpoint, path: "/api/health", method: "GET"),
      create(:route, :fast_endpoint, path: "/api/status", method: "GET"),
      create(:route, :fast_endpoint, path: "/api/ping", method: "POST")
    ]

    @slow_routes = [
      create(:route, :slow_endpoint, path: "/api/users", method: "GET"),
      create(:route, :slow_endpoint, path: "/api/orders", method: "POST")
    ]

    @critical_routes = [
      create(:route, :critical_endpoint, path: "/admin/heavy_import", method: "POST")
    ]
  end

  def create_performance_categorized_queries
    @fast_queries = [
      create(:query, :select_query, normalized_sql: "SELECT id FROM users WHERE id = ?"),
      create(:query, :select_query, normalized_sql: "SELECT name FROM categories WHERE active = ?")
    ]

    @slow_queries = [
      create(:query, :complex_query, normalized_sql: "SELECT u.*, p.* FROM users u LEFT JOIN profiles p ON u.id = p.user_id WHERE u.active = ?"),
      create(:query, :select_query, normalized_sql: "SELECT * FROM orders o JOIN users u ON o.user_id = u.id WHERE o.status = ?")
    ]

    @critical_queries = [
      create(:query, :complex_query, normalized_sql: "SELECT * FROM audit_logs WHERE created_at BETWEEN ? AND ? ORDER BY created_at")
    ]
  end

  def create_performance_categorized_requests
    # Create requests for routes
    (@fast_routes + @slow_routes + @critical_routes).each do |route|
      avg_duration = case route.path
      when "/api/health", "/api/status", "/api/ping" then 200
      when "/api/users", "/api/orders" then 800
      when "/admin/heavy_import" then 4000
      else 500
      end

      create_requests_for_route(route, avg_duration: avg_duration, count: 15, time_spread: :recent)
    end
  end

  def create_performance_categorized_operations
    # Create operations for queries
    (@fast_queries + @slow_queries + @critical_queries).each do |query|
      avg_duration = case query.normalized_sql
      when /SELECT id FROM users/, /SELECT name FROM categories/ then 50
      when /LEFT JOIN/, /JOIN users/ then 200
      when /audit_logs/ then 1500
      else 100
      end

      create_operations_for_query(query, avg_duration: avg_duration, count: 10, time_spread: :recent)
    end
  end

  def create_requests_for_route(route, avg_duration:, count:, time_spread:)
    base_time = case time_spread
    when :recent then 2.hours.ago
    else 3.days.ago
    end

    count.times do |i|
      duration_variation = (avg_duration * 0.4 * rand) - (avg_duration * 0.2)
      actual_duration = [ 1, avg_duration + duration_variation ].max.round

      create(:request,
        route: route,
        duration: actual_duration,
        occurred_at: base_time + (i * 10).minutes,
        status: rand(20) == 0 ? 500 : 200,
        is_error: rand(20) == 0
      )
    end
  end

  def create_operations_for_query(query, avg_duration:, count:, time_spread:)
    base_time = case time_spread
    when :recent then 2.hours.ago
    else 3.days.ago
    end

    count.times do |i|
      duration_variation = (avg_duration * 0.4 * rand) - (avg_duration * 0.2)
      actual_duration = [ 1, avg_duration + duration_variation ].max.round

      # Create a request first since operation requires one
      unique_path = "/test/query/#{query.id}/#{i}/#{rand(10000)}"
      request = create(:request,
        route: create(:route, path: unique_path, method: "GET"),
        duration: actual_duration,
        occurred_at: base_time + (i * 10).minutes,
        status: rand(20) == 0 ? 500 : 200,
        is_error: rand(20) == 0
      )

      create(:operation,
        request: request,
        query: query,
        duration: actual_duration,
        occurred_at: base_time + (i * 10).minutes,
        operation_type: "sql",
        label: query.normalized_sql
      )
    end
  end

  def create_summary_data_for_dashboard
    # Create summary data for recent time periods
    service = RailsPulse::SummaryService.new("day", 2.days.ago.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("hour", 2.hours.ago.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("day", Time.current.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("hour", Time.current.beginning_of_hour)
    service.perform
  end

  def all_test_routes
    @fast_routes + @slow_routes + @critical_routes
  end

  def all_test_queries
    @fast_queries + @slow_queries + @critical_queries
  end
end
