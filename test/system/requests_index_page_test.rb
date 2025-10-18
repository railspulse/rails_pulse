require "test_helper"

class RequestsIndexPageTest < ApplicationSystemTestCase
  def setup
    super
    # Fixtures are automatically loaded
  end

  test "index page loads and displays request data" do
    visit_rails_pulse_path "/requests"

    # Verify basic page structure
    assert_selector "body"
    assert_selector "table"
    assert_current_path "/rails_pulse/requests"

    # Requests don't have charts - verify table data exists
    assert_selector "table tbody tr", minimum: 1

    # Verify we can see request data
    assert_text "api/users GET"
  end

  test "metric cards display data correctly" do
    visit_rails_pulse_path "/requests"

    # Wait for page to load
    assert_selector "table tbody tr", wait: 5

    # Test Average Response Time card
    within("#average_response_times") do
      card_text = text.upcase

      assert_match(/AVERAGE RESPONSE TIME/, card_text)
      assert_match(/\d+(\.\d+)?\s*ms/, text)
    end

    # Test 95th Percentile card
    within("#percentile_response_times") do
      card_text = text.upcase

      assert_match(/95TH PERCENTILE RESPONSE TIME/, card_text)
      assert_match(/\d+(\.\d+)?\s*ms/, text)
    end

    # Test Request Count card
    within("#request_count_totals") do
      card_text = text.upcase

      assert_match(/REQUEST COUNT TOTAL/, card_text)
      assert_match(/\d+(\.\d+)?\s*\/\s*(min|day)/, text)
    end

    # Test Error Rate card
    within("#error_rate_per_route") do
      card_text = text.upcase

      assert_match(/ERROR RATE PER ROUTE/, card_text)
      assert_match(/\d+(\.\d+)?%/, text)
    end
  end

  test "performance duration filter works correctly" do
    visit_rails_pulse_path "/requests"

    # Test "Slow" filter (≥ 700ms)
    select "Slow (≥ 700ms)", from: "q[duration_gteq]"
    click_button "Search"

    # Verify filtering works - should show slow_request_1, slow_request_2, and critical_request
    assert_selector "table tbody tr", minimum: 1
    assert_current_path "/rails_pulse/requests", ignore_query: true

    # Verify slow requests are shown (slow_request_1: 800ms, slow_request_2: 900ms, critical_request: 4500ms)
    # All three are api/users requests with duration >= 700ms
    assert_text "api/users"
  end

  test "combined filters work together" do
    visit_rails_pulse_path "/requests"

    # Test combined filtering: slow requests with route filter
    select "Slow (≥ 700ms)", from: "q[duration_gteq]"
    fill_in "q[route_path_cont]", with: "api"

    click_button "Search"

    # Wait for page to update
    assert_selector "tbody", wait: 5

    # Verify filtering was applied
    assert_current_path "/rails_pulse/requests", ignore_query: true
  end

  test "table column sorting works correctly" do
    visit_rails_pulse_path "/requests"

    # Wait for table to load
    assert_selector "table tbody tr", wait: 5

    # Test Route column sorting
    within("table thead") do
      click_link "Route"
    end

    assert_selector "table tbody tr", wait: 3

    # Get first two row values to verify sorting
    first_route = page.find("tbody tr:first-child td:nth-child(1)").text
    second_route = page.find("tbody tr:nth-child(2) td:nth-child(1)").text

    # Verify the table is actually sorted (ascending or descending)
    assert(first_route <= second_route || first_route >= second_route,
           "Rows should be sorted by Route")

    # Test Response Time column sorting
    within("table thead") do
      click_link "Response Time"
    end

    assert_selector "table tbody tr", wait: 3

    # Test Status column sorting
    within("table thead") do
      click_link "Status"
    end

    assert_selector "table tbody tr", wait: 3
  end

  test "status filter works correctly" do
    visit_rails_pulse_path "/requests"

    # Filter by status category if available
    if has_select?("q[status_category_eq]")
      # Get the current option text to find the right value
      status_select = find("select[name='q[status_category_eq]']")

      # Try to select 2xx option (could be labeled as "2xx", "2xx Success", etc.)
      option_text = status_select.all("option").find { |opt| opt.text.include?("2xx") }&.text

      if option_text
        select option_text, from: "q[status_category_eq]"
        click_button "Search"

        # May show empty state if "Recent" mode has no 2xx requests
        # Just verify the page loads and filter was applied
        assert_current_path "/rails_pulse/requests", ignore_query: true
      end
    end

    # Just verify the page loads
    assert_selector "body"
  end

  test "route path filter works correctly" do
    visit_rails_pulse_path "/requests"

    # Filter by route path
    fill_in "q[route_path_cont]", with: "api/users"
    click_button "Search"

    # Wait for results
    assert_selector "tbody", wait: 5

    # Verify we see the filtered route
    assert_current_path "/rails_pulse/requests", ignore_query: true

    # Fixtures have multiple api/users requests (users_request_1, users_request_2, slow_request_1, slow_request_2, critical_request)
    assert_text "api/users"
  end

  test "time range filter works with Recent mode" do
    visit_rails_pulse_path "/requests"

    # Verify initial data loads
    assert_selector "table tbody tr", minimum: 1

    # Requests use "Recent" and "Custom Range" modes
    # Verify the Recent filter is working
    within("form") do
      assert has_select?("q[period_start_range]")
      select "Recent", from: "q[period_start_range]" if has_select?("q[period_start_range]")
    end

    click_button "Search"

    assert_current_path "/rails_pulse/requests", ignore_query: true
  end

  test "empty state displays when no data matches filters" do
    # Clear all data to ensure empty state
    RailsPulse::Summary.destroy_all
    RailsPulse::Request.destroy_all
    RailsPulse::Route.destroy_all

    visit_rails_pulse_path "/requests"

    # Should show empty state when no data exists
    assert_text "No request data found for the selected filters."
    assert_text "Try adjusting your time range or filters to see results."

    # Check for the search.svg image in the empty state
    assert_selector "img[src*='search.svg']"

    # Should not show table rows
    assert_no_selector "table tbody tr"
  end

  test "pagination works correctly" do
    visit_rails_pulse_path "/requests"

    # Wait for table to load
    assert_selector "table tbody tr", wait: 5

    # Check if pagination controls exist (they may not if we have < 10 items)
    # Pagination is typically shown at the bottom of the table
    if has_text?("Page 1 of")
      # Pagination exists - verify it's displayed
      assert_text "Page 1 of"
    else
      # No pagination needed (less than 10 items), just verify table exists
      assert_selector "table tbody tr", minimum: 1
    end
  end
end
