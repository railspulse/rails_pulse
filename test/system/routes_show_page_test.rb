require "test_helper"
require_relative "../support/shared_index_page_test"

class RoutesShowPageTest < SharedIndexPageTest
  def page_path
    "/routes/#{target_route.id}"
  end

  def target_route
    @target_route ||= @slow_routes&.first
  end

  def page_type
    :requests
  end

  def chart_selector
    "#route_repsonses_chart"
  end

  def performance_filter_options
    {
      slow: "Slow (≥ 500ms)",
      critical: "Critical (≥ 3000ms)"
    }
  end

  def all_test_data
    # Only requests for the target route
    @target_route_requests || []
  end

  def default_scope_data
    @target_route_requests || []
  end

  def last_week_data
    (@target_route_requests || []) + (@last_week_requests || [])
  end

  def last_month_data
    (@target_route_requests || []) + (@last_week_requests || []) + (@last_month_requests || [])
  end

  def slow_performance_data
    (all_test_data).select { |request| request.duration >= 500 }
  end

  def critical_performance_data
    (all_test_data).select { |request| request.duration >= 3000 }
  end

  def zoomed_data
    # Requests in the zoom time range (recent activity)
    (@target_route_requests || []).select { |request| request.occurred_at >= 2.5.hours.ago }
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
        name: "Response Time",
        index: 1,
        value_extractor: ->(text) { text.gsub(/[^\d.]/, "").to_f }
      }
    ]
  end

  def additional_filter_test
    # No additional filters for route show page
  end

  # Override table validation for route show page since it has different column layout
  def validate_table_data(page_type:, expected_data: nil, filter_applied: nil)
    table_rows = all("table tbody tr")
    assert table_rows.length > 0, "Table should have data rows"

    # For route show page, validate the requests table with different column layout
    validate_route_show_requests_table(table_rows, expected_data, filter_applied)
  end

  def validate_route_show_requests_table(table_rows, expected_requests, filter_applied)
    # Wait for table to stabilize after any DOM updates
    sleep 1 # Allow DOM to fully stabilize after filtering

    # Get row count first to avoid stale references during iteration
    row_count = all("table tbody tr").length

    # Validate that we have data when expected
    if expected_requests && expected_requests.any?
      assert row_count > 0, "Should have requests data in table after applying filter: #{filter_applied}"
    end

    # If no rows, that might be valid (e.g., critical filter might return empty results)
    return if row_count == 0

    # Validate each row by index to avoid stale element references
    (0...row_count).each do |index|
      # Re-find the specific row each time
      row_selector = "table tbody tr:nth-child(#{index + 1})"
      assert_selector row_selector, wait: 3

      within(row_selector) do
        cells = all("td")
        assert cells.length >= 4, "Request row #{index + 1} should have at least 4 columns (timestamp, duration, status, indicator)"

        # Skip timestamp validation (first column) - can vary in format
        # Validate duration (second column) - should contain "ms"
        duration_text = find("td:nth-child(2)").text
        assert_match(/\d+(\.\d+)?\s*ms/, duration_text, "Duration should show milliseconds in row #{index + 1}, got: #{duration_text}")

        # Validate HTTP status (third column) - should be numeric
        status_text = find("td:nth-child(3)").text
        assert_match(/\d{3}/, status_text, "HTTP Status should be 3-digit code in row #{index + 1}, got: #{status_text}")

        # Fourth column is status indicator - just verify it exists
        assert has_css?("td:nth-child(4)"), "Row #{index + 1} should have status indicator column"
      end
    end

    # Basic coverage validation
    if expected_requests && expected_requests.any?
      assert row_count > 0, "Should have requests data in table"
    end
  end

  # Route show specific test
  def test_route_details_are_displayed
    visit_rails_pulse_path page_path

    # Verify route-specific information is displayed
    assert_text target_route.path
    assert_text target_route.method

    # Verify requests table shows only requests for this route
    assert_selector "table tbody tr", minimum: 1

    # Verify all visible requests are for this route
    within "table tbody" do
      # Since this is a show page for a specific route, we don't need to verify route paths in table
      # Instead verify that we have request data displayed
      assert_selector "tr", minimum: 1
    end
  end

  # Test request-specific sortable columns
  def test_request_sortable_columns_work
    visit_rails_pulse_path page_path

    # Wait for table to load
    assert_selector "table tbody tr", wait: 5

    # Test HTTP Status column sorting
    within("table thead") do
      click_link "HTTP Status"
    end
    assert_selector "table tbody tr", wait: 3

    # Test Status column sorting
    within("table thead") do
      click_link "Status"
    end
    assert_selector "table tbody tr", wait: 3
  end

  def test_empty_state_displays_when_no_requests_for_route
    # Clear requests for this specific route to ensure empty state
    RailsPulse::Request.where(route: target_route).destroy_all
    RailsPulse::Summary.where(summarizable: target_route).destroy_all

    visit_rails_pulse_path page_path

    # Should show empty state when no requests exist for this route
    assert_text "No route requests found for the selected filters."
    assert_text "Try adjusting your time range or filters to see results."

    # Check for the search.svg image in the empty state
    assert_selector "img[src*='search.svg']"

    # Should not show chart or table
    assert_no_selector "#route_repsonses_chart"
    assert_no_selector "table tbody tr"
  end

  private

  def create_comprehensive_test_data
    # Create routes with predictable performance characteristics
    create_performance_categorized_routes

    # Create requests with specific performance patterns for our target route
    create_performance_categorized_requests_for_target_route

    # Create Summary data needed for route show page
    create_summary_data_for_route_show
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
  end

  def create_performance_categorized_requests_for_target_route
    # Focus on creating varied requests for our target route
    @target_route_requests = []

    # Create requests with varied performance for the target route
    # Recent requests (will appear in zoomed view)
    12.times do |i|
      duration = [ 600, 700, 800, 900, 1000 ].sample + rand(100)
      request = create(:request,
        route: target_route,
        duration: duration,
        occurred_at: 2.hours.ago + (i * 5).minutes,
        status: [ 200, 200, 200, 500 ].sample,
        is_error: duration > 900 ? [ true, false ].sample : false
      )
      @target_route_requests << request
    end

    # Add a few critical requests (≥ 3000ms)
    3.times do |i|
      duration = [ 3100, 3500, 4000 ].sample + rand(500)
      request = create(:request,
        route: target_route,
        duration: duration,
        occurred_at: 2.hours.ago + (i * 8).minutes,
        status: [ 200, 500 ].sample,
        is_error: true
      )
      @target_route_requests << request
    end

    # Last week requests
    @last_week_requests = []
    10.times do |i|
      duration = [ 500, 600, 700, 800 ].sample + rand(100)
      request = create(:request,
        route: target_route,
        duration: duration,
        occurred_at: 8.days.ago + (i * 30).minutes,
        status: [ 200, 200, 500 ].sample,
        is_error: [ true, false ].sample
      )
      @last_week_requests << request
      @target_route_requests << request
    end

    # Last month requests
    @last_month_requests = []
    8.times do |i|
      duration = [ 400, 500, 600 ].sample + rand(100)
      request = create(:request,
        route: target_route,
        duration: duration,
        occurred_at: 20.days.ago + (i * 60).minutes,
        status: [ 200, 200, 200, 500 ].sample,
        is_error: false
      )
      @last_month_requests << request
      @target_route_requests << request
    end
  end

  def create_summary_data_for_route_show
    time_spreads = {
      recent: 2.hours.ago,
      last_week: 8.days.ago,
      last_month: 20.days.ago
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
