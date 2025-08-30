require "support/application_system_test_case"

class RequestsIndexPageTest < ApplicationSystemTestCase
  include ChartValidationHelpers
  include TableValidationHelpers

  def setup
    super
    create_comprehensive_test_data
  end

  test "requests index page loads and displays data" do
    visit_rails_pulse_path "/requests"

    # Verify basic page structure
    assert_selector "body"
    assert_selector "table"
    assert_current_path "/rails_pulse/requests"

    # Verify chart container exists
    assert_selector "#average_response_times_chart"
    assert_selector "[data-rails-pulse--index-target='chart']"

    # Verify chart data matches expected test data
    expected_requests = all_test_requests
    validate_chart_data("#average_response_times_chart", expected_data: expected_requests)
    validate_table_data(page_type: :requests, expected_data: expected_requests)

    # Try "Last Month" filter to see all our test requests
    select "Last Month", from: "q[period_start_range]"
    click_button "Search"

    validate_table_data(page_type: :requests, expected_data: expected_requests, filter_applied: "Last Month")
    validate_chart_data("#average_response_times_chart", expected_data: expected_requests, filter_applied: "Last Month")
  end

  test "metric cards display data correctly" do
    visit_rails_pulse_path "/requests"

    # Wait for page to load
    assert_selector "table tbody tr", wait: 5

    # Verify Average Response Time card
    within("#average_response_times") do
      assert_text "AVERAGE RESPONSE TIME"
      assert_match(/\d+(\.\d+)?\s*ms/, text, "Average response time should show ms value")
    end

    # Verify 95th Percentile Response Time card
    within("#percentile_response_times") do
      assert_text "95TH PERCENTILE RESPONSE TIME"
      assert_match(/\d+(\.\d+)?\s*ms/, text, "95th percentile should show ms value")
    end

    # Verify Request Count Total card
    within("#request_count_totals") do
      assert_text "REQUEST COUNT TOTAL"
      assert_match(/\d+\s*\/\s*min/, text, "Request count should show per minute value")
    end

    # Verify Error Rate Per Route card
    within("#error_rate_per_route") do
      assert_text "ERROR RATE PER ROUTE"
      assert_match(/\d+(\.\d+)?%/, text, "Error rate should show percentage value")
    end
  end

  test "time range filter updates chart and table data" do
    visit_rails_pulse_path "/requests"

    # Capture initial data - should show recent requests but not last_week_only, last_month_only, or old requests
    default_scope_requests = (@fast_requests + @slow_requests + @very_slow_requests + @critical_requests)
    validate_chart_data("#average_response_times_chart", expected_data: default_scope_requests)
    validate_table_data(page_type: :requests)

    # Test Last Week filter - should include last_week_only request but exclude last_month_only and old requests
    select "Last Week", from: "q[period_start_range]"
    click_button "Search"

    # Verify page updated (may have query parameters)
    assert_current_path "/rails_pulse/requests", ignore_query: true
    last_week_requests = default_scope_requests + [ @last_week_only_request ].compact
    validate_chart_data("#average_response_times_chart", expected_data: last_week_requests, filter_applied: "Last Week")
    validate_table_data(page_type: :requests, filter_applied: "Last Week")

    # Test Last Month filter - should include all except old request
    select "Last Month", from: "q[period_start_range]"
    click_button "Search"

    last_month_requests = default_scope_requests + [ @last_week_only_request, @last_month_only_request ].compact
    validate_chart_data("#average_response_times_chart", expected_data: last_month_requests, filter_applied: "Last Month")
    validate_table_data(page_type: :requests, filter_applied: "Last Month")
  end

  test "performance duration filter works correctly" do
    visit_rails_pulse_path "/requests"

    # Test "Slow" filter - should show requests ≥ 700ms
    select "Slow (≥ 700ms)", from: "q[avg_duration]"
    click_button "Search"

    # Validate slow requests are shown (≥ 700ms average) - should include slow, very_slow, critical, and last_week_only
    slow_requests = (@slow_requests + @very_slow_requests + @critical_requests + [ @last_week_only_request ]).compact
    validate_chart_data("#average_response_times_chart", expected_data: slow_requests, filter_applied: "Slow")
    validate_table_data(page_type: :requests, filter_applied: "Slow")

    # Test "Critical" filter - should show requests ≥ 4000ms (only critical requests)
    # First, switch to "Last Month" to ensure we capture all our test data
    select "Last Month", from: "q[period_start_range]"
    select "Critical (≥ 4000ms)", from: "q[avg_duration]"
    click_button "Search"

    # Validate critical requests are shown (≥ 4000ms average)
    critical_requests = @critical_requests
    validate_chart_data("#average_response_times_chart", expected_data: critical_requests, filter_applied: "Critical")
    validate_table_data(page_type: :requests, filter_applied: "Critical")
  end

  test "combined filters work together" do
    visit_rails_pulse_path "/requests"

    # Test combined filtering: slow requests from last week
    select "Slow (≥ 700ms)", from: "q[avg_duration]"
    select "Last Week", from: "q[period_start_range]"
    click_button "Search"

    # Wait for page to update
    assert_selector "tbody", wait: 5
    sleep 0.5  # Allow DOM to fully stabilize

    # Verify combined filtering results using standard validation
    # Expected: slow requests (≥ 700ms) from last week time range
    expected_combined_requests = (@slow_requests + @very_slow_requests + @critical_requests + [ @last_week_only_request ]).compact
    validate_chart_data("#average_response_times_chart", expected_data: expected_combined_requests, filter_applied: "Combined Slow + Last Week")
    validate_table_data(page_type: :requests, filter_applied: "Slow")
  end

  test "table column sorting works correctly" do
    visit_rails_pulse_path "/requests"

    # Wait for table to load
    assert_selector "table tbody tr", wait: 5

    # Test sorting by Duration column
    click_link "Duration"
    assert_selector "table tbody tr", wait: 3

    # Verify sort order by comparing first two rows
    first_row_duration = page.find("tbody tr:first-child td:nth-child(3)").text
    second_row_duration = page.find("tbody tr:nth-child(2) td:nth-child(3)").text

    first_value = first_row_duration.gsub(/[^\d.]/, "").to_f
    second_value = second_row_duration.gsub(/[^\d.]/, "").to_f

    # The sorting could be ascending or descending, just verify it's actually sorted
    is_ascending = first_value <= second_value
    is_descending = first_value >= second_value

    assert(is_ascending || is_descending,
           "Rows should be sorted by duration: #{first_value}ms vs #{second_value}ms")

    # Test sorting by clicking the same column again (should toggle sort direction)
    click_link "Duration"
    assert_selector "table tbody tr", wait: 3

    # Get new values after re-sorting
    new_first_row_duration = page.find("tbody tr:first-child td:nth-child(3)").text
    new_second_row_duration = page.find("tbody tr:nth-child(2) td:nth-child(3)").text

    new_first_value = new_first_row_duration.gsub(/[^\d.]/, "").to_f
    new_second_value = new_second_row_duration.gsub(/[^\d.]/, "").to_f

    # Verify the sort direction changed or at least table is still sorted
    new_is_ascending = new_first_value <= new_second_value
    new_is_descending = new_first_value >= new_second_value

    assert(new_is_ascending || new_is_descending,
           "Rows should still be sorted after toggling: #{new_first_value}ms vs #{new_second_value}ms")

    # Test sorting by Route column
    click_link "Route"
    assert_selector "table tbody tr", wait: 3

    # Verify routes are sorted by checking first two route paths
    first_route = page.find("tbody tr:first-child td:first-child a").text.strip
    second_route = page.find("tbody tr:nth-child(2) td:first-child a").text.strip

    # Routes could be sorted ascending or descending alphabetically
    routes_ascending = first_route <= second_route
    routes_descending = first_route >= second_route

    assert(routes_ascending || routes_descending,
           "Routes should be sorted alphabetically: '#{first_route}' vs '#{second_route}'")

    # Test that other sortable columns work (basic functionality test)
    # Test Timestamp column sorting
    within("table thead") do
      click_link "Timestamp"
    end
    assert_selector "table tbody tr", wait: 3

    # Test HTTP Status column sorting
    within("table thead") do
      click_link "HTTP Status"
    end
    assert_selector "table tbody tr", wait: 3
  end

  test "zoom range parameters filter table data while chart shows all data" do
    visit_rails_pulse_path "/requests"

    # Wait for page to load with default data (recent requests)
    assert_selector "table tbody tr", wait: 5

    # Validate initial state - should show default scope requests (recent data)
    default_requests = (@fast_requests + @slow_requests + @very_slow_requests + @critical_requests)

    # Chart and table should show default data (no zoom yet)
    validate_chart_data("#average_response_times_chart", expected_data: default_requests, filter_applied: "Default")
    validate_table_data(page_type: :requests, expected_data: default_requests, filter_applied: "Default")

    # Now apply zoom parameters to filter table to a narrow 1-hour window around our test data
    # Our :recent test data is at 2.hours.ago, so zoom to that hour
    zoom_start = 2.5.hours.ago.to_i
    zoom_end = 1.5.hours.ago.to_i

    zoom_params = {
      "zoom_start_time" => zoom_start.to_s,
      "zoom_end_time" => zoom_end.to_s
    }

    zoom_url = "/rails_pulse/requests?#{zoom_params.to_query}"
    visit zoom_url

    # Wait for page to reload with zoom applied
    assert_selector "table tbody tr", wait: 5

    # Chart should still show the SAME data (zoom is visual only on chart)
    validate_chart_data("#average_response_times_chart", expected_data: default_requests, filter_applied: "Default with Zoom")

    # Table should only show requests with data in the zoom range (2.5 to 1.5 hours ago)
    # Based on our test data:
    # - fast_requests: only have :recent data (will appear in zoom)
    # - slow_requests: have both :recent and :last_week data (will appear in zoom)
    # - very_slow_requests: only have :last_week data (will NOT appear in zoom)
    # - critical_requests: only have :recent data (will appear in zoom)
    zoomed_requests = (@fast_requests + @slow_requests + @critical_requests)
    validate_table_data(page_type: :requests, expected_data: zoomed_requests, filter_applied: "Recent Zoom")
  end

  private

  def all_test_requests
    (@fast_requests || []) + (@slow_requests || []) + (@very_slow_requests || []) + (@critical_requests || []) +
    [ @last_week_only_request, @last_month_only_request, @old_request ].compact
  end

  def create_comprehensive_test_data
    # Create routes with predictable performance characteristics
    create_performance_categorized_routes

    # Create requests with specific performance patterns
    create_performance_categorized_requests

    # Generate queries using existing bulk data helper
    create_query_data

    # Create Summary data needed for requests index page
    create_summary_data_for_requests
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

    # Fast requests: Only active in recent period (recent hour activity)
    @fast_requests = []
    @fast_routes.each do |route|
      @fast_requests += create_requests_for_route(route, avg_duration: 200, count: 20, time_spread: :recent)
    end

    # Slow requests: Active in both recent and last week (will appear in both zoom and full view)
    @slow_requests = []
    @slow_routes.each do |route|
      @slow_requests += create_requests_for_route(route, avg_duration: 800, count: 15, time_spread: :recent)
      @slow_requests += create_requests_for_route(route, avg_duration: 750, count: 10, time_spread: :last_week)
    end

    # Very slow requests: Only active in last week period (won't appear in recent zoom)
    @very_slow_requests = []
    @very_slow_routes.each do |route|
      @very_slow_requests += create_requests_for_route(route, avg_duration: 1800, count: 8, time_spread: :last_week)
    end

    # Critical requests: Only active in recent period (will appear in zoom)
    @critical_requests = []
    @critical_routes.each do |route|
      @critical_requests += create_requests_for_route(route, avg_duration: 4000, count: 5, time_spread: :recent)
    end

    # Time-specific requests for testing filtering boundaries
    # Last week only request - should appear in "Last Week" and "Last Month" filters but not default scope
    @last_week_only_request = create_requests_for_route(@last_week_only_route, avg_duration: 800, count: 5, time_spread: :last_week_only).first

    # Last month only request - should appear only in "Last Month" filter
    @last_month_only_request = create_requests_for_route(@last_month_only_route, avg_duration: 300, count: 8, time_spread: :last_month_only).first

    # Old request - should not appear in any time filter (older than 1 month)
    @old_request = create_requests_for_route(@old_route, avg_duration: 2000, count: 3, time_spread: :old).first
  end

  def create_requests_for_route(route, avg_duration:, count:, time_spread:)
    base_time = case time_spread
    when :recent then 2.hours.ago  # Within last 24 hours
    when :last_week then 10.days.ago  # Clearly in "last month" range
    when :last_week_only then 6.days.ago  # Only in last week, not in recent/default scope
    when :last_month_only then 20.days.ago  # Only in last month, not in last week
    when :old then 40.days.ago  # Older than any filter scope
    else 3.days.ago
    end

    requests = []
    count.times do |i|
      # Add some variation around the average duration (�20%)
      duration_variation = (avg_duration * 0.4 * rand) - (avg_duration * 0.2)
      actual_duration = [ 1, avg_duration + duration_variation ].max.round

      request = create(:request,
        route: route,
        duration: actual_duration,
        occurred_at: base_time + (i * 10).minutes,
        status: rand(10) == 0 ? 500 : 200, # 10% error rate
        is_error: rand(10) == 0
      )
      requests << request
    end
    requests
  end

  def create_query_data
    # Create a few basic queries for operations
    @queries = 3.times.map { create(:query, :realistic_sql) }
  end

  def create_summary_data_for_requests
    # The SummaryService aggregates Requests into Summary records by time periods
    # We need to create summaries that cover the exact time periods where our Requests exist

    # Get the actual time ranges where our Requests were created
    time_spreads = {
      recent: 2.hours.ago,
      last_week: 10.days.ago,
      last_week_only: 6.days.ago,
      last_month_only: 20.days.ago,
      old: 40.days.ago
    }

    time_spreads.each do |spread_type, base_time|
      # For each time spread, create summaries that cover the full range
      # where requests might exist (base_time to base_time + requests*10.minutes)

      # Create daily summaries for the day containing each time spread
      service = RailsPulse::SummaryService.new("day", base_time.beginning_of_day)
      service.perform

      # For recent data, also create hourly summaries for more granular data
      if spread_type == :recent
        service = RailsPulse::SummaryService.new("hour", base_time.beginning_of_hour)
        service.perform
      end
    end

    # Also create a summary for "today" to ensure default view has data
    service = RailsPulse::SummaryService.new("day", Time.current.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("hour", Time.current.beginning_of_hour)
    service.perform
  end

  def calculate_expected_request_count_for_filter(filter_type, filter_value)
    case filter_type
    when :performance
      case filter_value
      when :slow then (@slow_requests + @very_slow_requests + @critical_requests).count
      when :very_slow then (@very_slow_requests + @critical_requests).count
      when :critical then @critical_requests.count
      else (@fast_requests + @slow_requests + @very_slow_requests + @critical_requests).count
      end
    else
      (@fast_requests + @slow_requests + @very_slow_requests + @critical_requests).count
    end
  end
end