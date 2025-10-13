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
    RailsPulse::Request.all.to_a
  end

  def default_scope_data
    all_test_data
  end

  def last_week_data
    all_test_data
  end

  def last_month_data
    all_test_data
  end

  def slow_performance_data
    # Requests with slow duration (≥ 700ms)
    all_test_data.select { |request| request.duration >= 700 }
  end

  def critical_performance_data
    # Requests with critical duration (≥ 4000ms)
    all_test_data.select { |request| request.duration >= 4000 }
  end

  def zoomed_data
    # Requests in the zoom time range (recent activity)
    RailsPulse::Request.where("occurred_at >= ?", 2.5.hours.ago).to_a
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
        name: "Route",
        index: 1,
        value_extractor: ->(text) { text.strip }
      }
    ]
  end

  def additional_filter_test
    # No additional filters for requests index page
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

    # Test Status column sorting
    within("table thead") do
      click_link "Status"
    end

    assert_selector "table tbody tr", wait: 3
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

  private

  def create_comprehensive_test_data
    # Create additional requests with varying performance for testing filters
    create_additional_test_requests
    create_summary_data_for_requests
  end

  def create_additional_test_requests
    # Add some additional requests with different performance characteristics
    # to test the performance filters

    # Add some slow requests (≥ 700ms)
    2.times do |i|
      RailsPulse::Request.create!(
        route: @api_users_route,
        duration: 800 + (i * 100),
        status: 200,
        is_error: false,
        request_uuid: "slow-req-#{i}",
        controller_action: "UsersController#index",
        occurred_at: 2.hours.ago + (i * 10).minutes
      )
    end

    # Add a critical request (≥ 4000ms)
    RailsPulse::Request.create!(
      route: @api_users_route,
      duration: 4500,
      status: 500,
      is_error: true,
      request_uuid: "critical-req-1",
      controller_action: "UsersController#heavy_operation",
      occurred_at: 1.hour.ago
    )
  end

  def create_summary_data_for_requests
    # Create summary data for the time periods used in requests index tests
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
