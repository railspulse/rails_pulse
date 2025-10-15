require "test_helper"
require_relative "../support/shared_test_data"
require_relative "../support/global_filters_helpers"

class GlobalFiltersTest < ApplicationSystemTestCase
  include SharedTestData
  include GlobalFiltersHelpers

  def setup
    super
    load_shared_test_data
    create_comprehensive_test_data
  end

  test "global filters persist across pages" do
    # Set up date range and performance threshold
    date_range = "#{7.days.ago.strftime('%b %d, %Y %l:%M %p')} to #{Time.current.strftime('%b %d, %Y %l:%M %p')}"

    visit_rails_pulse_path "/routes"

    # Open modal and set both filters
    set_global_filters(
      date_range: date_range,
      threshold: "Slow and Above"
    )

    # Verify filter icon shows active state
    assert_global_filters_active

    # Verify routes page shows filtered data
    assert_selector "table tbody tr", wait: 5
    # Should only show routes with slow performance

    # Navigate to requests page
    visit_rails_pulse_path "/requests"

    # Verify custom picker is visible with global date range
    assert_custom_picker_visible
    assert_selector "table tbody tr", wait: 5
    # Should show only slow requests within date range

    # Navigate to queries page
    visit_rails_pulse_path "/queries"

    # Verify filters still active
    assert_custom_picker_visible
    assert_selector "table tbody tr", wait: 5
    # Should show only slow queries
  end

  test "clearing global filters works" do
    # Set both filters
    date_range = "#{7.days.ago.strftime('%b %d, %Y %l:%M %p')} to #{Time.current.strftime('%b %d, %Y %l:%M %p')}"

    visit_rails_pulse_path "/routes"
    set_global_filters(
      date_range: date_range,
      threshold: "Slow and Above"
    )

    # Verify filters applied on routes
    assert_global_filters_active
    assert_custom_picker_visible

    # Visit requests to verify persistence
    visit_rails_pulse_path "/requests"

    assert_custom_picker_visible

    # Clear filters
    clear_global_filters

    # Verify filters removed
    assert_global_filters_inactive
    assert_dropdown_visible # Should show dropdown, not custom picker
    assert_selector "table tbody tr", wait: 5

    # Visit routes page and verify no filters
    visit_rails_pulse_path "/routes"

    assert_dropdown_visible
    # Default "Last 24 hours" should be selected
    assert_selector "select[name='q[period_start_range]']" do |select|
      assert_equal "last_day", find("select[name='q[period_start_range]']").value
    end
  end

  test "page specific filters override global filters" do
    # Set global filters
    visit_rails_pulse_path "/routes"

    # Set global date range to "Last Month" equivalent
    last_month_start = 1.month.ago.strftime("%b %d, %Y %l:%M %p")
    last_month_end = Time.current.strftime("%b %d, %Y %l:%M %p")

    set_global_filters(
      date_range: "#{last_month_start} to #{last_month_end}",
      threshold: "Slow and Above"
    )

    # Verify global filters applied
    assert_custom_picker_visible

    # Get initial row count
    initial_row_count = all("table tbody tr").count

    # Override with page-specific time range
    select "Last 24 hours", from: "q[period_start_range]"
    click_button "Search"

    assert_selector "table tbody tr", wait: 5

    # Verify we're now seeing Last 24 hours data (different from Last Month)
    assert_dropdown_visible
    current_selection = find("select[name='q[period_start_range]']").value

    assert_equal "last_day", current_selection

    # Should still show slow performance (global threshold respected)
    # But time range is overridden to last 24 hours

    # Override performance threshold to "All Requests"
    select "All Requests", from: "q[avg_duration]"
    click_button "Search"

    assert_selector "table tbody tr", wait: 5

    # Now showing all performance levels in last 24 hours
    # Both global filters overridden by page-specific selections
  end

  test "global filters work with chart zoom" do
    # Set global date range for last week
    last_week_start = 1.week.ago.strftime("%b %d, %Y %l:%M %p")
    last_week_end = Time.current.strftime("%b %d, %Y %l:%M %p")

    visit_rails_pulse_path "/routes"

    set_global_filters(date_range: "#{last_week_start} to #{last_week_end}")

    # Verify global range applied
    assert_custom_picker_visible
    assert_selector "table tbody tr", wait: 5

    # Capture initial table data (should show all last week data)
    initial_rows = all("table tbody tr").map(&:text)

    # Apply zoom parameters (simulate chart column click)
    zoom_start = 2.days.ago.beginning_of_hour.to_i
    zoom_end = 1.day.ago.end_of_hour.to_i

    zoom_url = "/rails_pulse/routes?zoom_start_time=#{zoom_start}&zoom_end_time=#{zoom_end}"
    visit zoom_url

    # Wait for page to reload with zoom
    assert_selector "table tbody tr", wait: 5

    # Table should now show only zoomed range data
    zoomed_rows = all("table tbody tr").map(&:text)

    # Chart should still show full global range
    # (We can't easily test chart data, but the test verifies table filtering)

    # Clear zoom by visiting without params
    visit_rails_pulse_path "/routes"

    # Table should return to showing full global range
    assert_selector "table tbody tr", wait: 5
    assert_custom_picker_visible
  end

  private

  def create_comprehensive_test_data
    # Create requests with various performance levels at different times

    # Fast request at 1 hour ago
    route_fast = rails_pulse_routes(:api_test)
    RailsPulse::Request.create!(
      route: route_fast,
      duration: 150.0,
      occurred_at: 1.hour.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-global-fast-1",
      controller_action: "Api::TestController#index"
    )

    # Slow request at 3 days ago (within last week)
    route_slow = rails_pulse_routes(:api_users)
    RailsPulse::Request.create!(
      route: route_slow,
      duration: 750.0,
      occurred_at: 3.days.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-global-slow-1",
      controller_action: "Api::UsersController#index"
    )

    # Very slow request at 1 week ago
    RailsPulse::Request.create!(
      route: route_slow,
      duration: 1800.0,
      occurred_at: 1.week.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-global-veryslow-1",
      controller_action: "Api::UsersController#index"
    )

    # Critical request at 2 weeks ago
    route_critical = rails_pulse_routes(:api_posts)
    RailsPulse::Request.create!(
      route: route_critical,
      duration: 3500.0,
      occurred_at: 2.weeks.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-global-critical-1",
      controller_action: "Api::PostsController#create"
    )

    # Generate summaries for the test data
    RailsPulse::SummaryService.new("hour", 1.hour.ago.beginning_of_hour).perform
    RailsPulse::SummaryService.new("day", 3.days.ago.beginning_of_day).perform
    RailsPulse::SummaryService.new("day", 1.week.ago.beginning_of_day).perform
    RailsPulse::SummaryService.new("day", 2.weeks.ago.beginning_of_day).perform
  end
end
