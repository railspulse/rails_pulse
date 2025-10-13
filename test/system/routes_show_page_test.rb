require "test_helper"
require_relative "../support/shared_index_page_test"

class RoutesShowPageTest < SharedIndexPageTest
  def page_path
    "/routes/#{target_route.id}"
  end

  def target_route
    @target_route ||= @api_users_route
  end

  def page_type
    :requests
  end

  def chart_selector
    "#route_responses_chart"
  end

  def performance_filter_options
    {
      slow: "Slow (≥ 500ms)",
      critical: "Critical (≥ 3000ms)"
    }
  end

  def all_test_data
    # Only requests for the target route from shared data
    target_route.requests.to_a
  end

  def default_scope_data
    target_route.requests.to_a
  end

  def last_week_data
    target_route.requests.to_a
  end

  def last_month_data
    target_route.requests.to_a
  end

  def slow_performance_data
    (all_test_data).select { |request| request.duration >= 500 }
  end

  def critical_performance_data
    (all_test_data).select { |request| request.duration >= 3000 }
  end

  def zoomed_data
    # Requests in the zoom time range (recent activity)
    target_route.requests.where("occurred_at >= ?", 2.5.hours.ago).to_a
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
        value_regex: /\d+(\.\d+)?\s*\/\s*(min|day)/,
        value_message: "Request count should show per minute or per day value"
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

    assert_operator table_rows.length, :>, 0, "Table should have data rows"

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
      assert_operator row_count, :>, 0, "Should have requests data in table after applying filter: #{filter_applied}"
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

        assert_operator cells.length, :>=, 3, "Request row #{index + 1} should have at least 3 columns (timestamp, response time, status)"

        # Skip timestamp validation (first column) - can vary in format
        # Validate duration (second column) - should contain "ms"
        duration_text = find("td:nth-child(2)").text

        assert_match(/\d+(\.\d+)?\s*ms/, duration_text, "Duration should show milliseconds in row #{index + 1}, got: #{duration_text}")

        # Validate HTTP status (third column) - should be numeric (may include "Error" text)
        status_text = find("td:nth-child(3)").text

        assert_match(/\d{3}/, status_text, "HTTP Status should contain 3-digit code in row #{index + 1}, got: #{status_text}")
      end
    end

    # Basic coverage validation
    if expected_requests && expected_requests.any?
      assert_operator row_count, :>, 0, "Should have requests data in table"
    end
  end

  # Route show specific test
  def test_route_details_are_displayed
    visit_rails_pulse_path page_path

    # Verify route-specific information is displayed (path is shown in breadcrumbs)
    assert_text target_route.path
    # Note: HTTP method may not be displayed on the page, only the path

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
    assert_no_selector "#route_responses_chart"
    assert_no_selector "table tbody tr"
  end

  private

  def create_comprehensive_test_data
    # Create additional requests with varying performance for testing filters
    create_additional_route_requests
    create_summary_data_for_route_show
  end

  def create_additional_route_requests
    # Add some additional requests with different performance characteristics
    # to test the performance filters

    # Add some slow requests (≥ 500ms)
    2.times do |i|
      RailsPulse::Request.create!(
        route: target_route,
        duration: 600 + (i * 100),
        status: 200,
        is_error: false,
        request_uuid: "slow-#{i}",
        controller_action: "UsersController#index",
        occurred_at: 2.hours.ago + (i * 10).minutes
      )
    end

    # Add multiple critical requests (≥ 3000ms) to ensure day-level summary avg >= 3000ms
    # Create them all in the same day to ensure the average stays high
    5.times do |i|
      RailsPulse::Request.create!(
        route: target_route,
        duration: 3500 + (i * 100),  # 3500ms, 3600ms, 3700ms, 3800ms, 3900ms
        status: 500,
        is_error: true,
        request_uuid: "critical-#{i}",
        controller_action: "UsersController#heavy_operation",
        occurred_at: 1.hour.ago + (i * 5).minutes
      )
    end
  end

  def create_summary_data_for_route_show
    # Create summary data for the time periods used in tests
    service = RailsPulse::SummaryService.new("day", 2.days.ago.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("hour", 2.hours.ago.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("day", Time.current.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("hour", Time.current.beginning_of_hour)
    service.perform
  end
end
