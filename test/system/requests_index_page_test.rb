require "test_helper"
require_relative "../support/shared_index_page_test"

class RequestsIndexPageTest < SharedIndexPageTest
  def page_path
    "/requests"
  end

  def page_type
    :requests
  end

  def chart_selector
    "#average_response_times_chart"
  end

  def performance_filter_options
    {
      slow: "Slow (≥ 700ms)",
      critical: "Critical (≥ 4000ms)"
    }
  end

  def all_test_data
    (@fast_requests || []) + (@slow_requests || []) + (@very_slow_requests || []) + (@critical_requests || []) +
    [ @last_week_only_request, @last_month_only_request, @old_request ].compact
  end

  def default_scope_data
    (@fast_requests + @slow_requests + @very_slow_requests + @critical_requests)
  end

  def last_week_data
    default_scope_data + [ @last_week_only_request ].compact
  end

  def last_month_data
    default_scope_data + [ @last_week_only_request, @last_month_only_request ].compact
  end

  def slow_performance_data
    (@slow_requests + @very_slow_requests + @critical_requests + [ @last_week_only_request ]).compact
  end

  def critical_performance_data
    @critical_requests
  end

  def zoomed_data
    (@fast_requests + @slow_requests + @critical_requests)
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
        name: "Route",
        index: 1,
        value_extractor: ->(text) { text.strip }
      }
    ]
  end

  # Test additional sortable columns specific to requests
  def test_additional_sortable_columns_work
    visit_rails_pulse_path "/requests"

    # Wait for table to load
    assert_selector "table tbody tr", wait: 5

    # Test Response Time column sorting
    within("table thead") do
      click_link "Response Time"
    end
    assert_selector "table tbody tr", wait: 3

    # Test HTTP Status column sorting
    within("table thead") do
      click_link "HTTP Status"
    end
    assert_selector "table tbody tr", wait: 3
  end

  private

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
    @last_week_only_request = create_requests_for_route(@last_week_only_route, avg_duration: 800, count: 5, time_spread: :last_week_only).first
    @last_month_only_request = create_requests_for_route(@last_month_only_route, avg_duration: 300, count: 8, time_spread: :last_month_only).first
    @old_request = create_requests_for_route(@old_route, avg_duration: 2000, count: 3, time_spread: :old).first
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

    requests = []
    count.times do |i|
      duration_variation = (avg_duration * 0.4 * rand) - (avg_duration * 0.2)
      actual_duration = [ 1, avg_duration + duration_variation ].max.round

      request = create(:request,
        route: route,
        duration: actual_duration,
        occurred_at: base_time + (i * 10).minutes,
        status: rand(10) == 0 ? 500 : 200,
        is_error: rand(10) == 0
      )
      requests << request
    end
    requests
  end

  def create_query_data
    @queries = 3.times.map { create(:query, :realistic_sql) }
  end

  def create_summary_data_for_requests
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

  def test_empty_state_displays_when_no_data_matches_filters
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

    # Should not show chart or table
    assert_no_selector "#average_response_times_chart"
    assert_no_selector "table tbody tr"
  end
end
