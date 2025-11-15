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
    @report_job = rails_pulse_jobs(:report_job)

    # Configure tags for testing
    RailsPulse.configure do |config|
      config.tags = [ "api", "users", "posts", "maintenance", "database", "critical" ]
    end
  end

  def teardown
    # Reset configuration
    RailsPulse.configure do |config|
      config.tags = []
    end
    super
  end

  test "global filters complete workflow" do
    visit_rails_pulse_path "/routes"

    # === STEP 1: Set global date range filter ===
    # Set date range that covers our test data (last 7 days)
    # Use Y-m-d H:i format which flatpickr expects for datetime type
    date_range_start = 7.days.ago.strftime("%Y-%m-%d %H:%M")
    date_range_end = Time.current.strftime("%Y-%m-%d %H:%M")

    set_global_filters(date_range: "#{date_range_start} to #{date_range_end}")

    # Verify filter icon shows active state
    assert_global_filters_active

    # Verify custom picker is visible (global date filter sets custom mode)
    assert_custom_picker_visible

    # Verify we have data displayed
    assert_selector "table tbody tr", wait: 5

    # === STEP 2: Verify global filters persist across different pages ===
    # Navigate to requests page
    visit_rails_pulse_path "/requests"

    # Global filter should still be active
    assert_global_filters_active
    assert_custom_picker_visible
    assert_selector "table tbody tr", wait: 5

    # Navigate to queries page
    visit_rails_pulse_path "/queries"

    # Global filter should still be active
    assert_global_filters_active
    assert_custom_picker_visible
    assert_selector "table tbody tr", wait: 5

    # Navigate to jobs page
    visit_rails_pulse_path "/jobs"

    assert_global_filters_active
    assert_selector "table tbody tr", wait: 5
    assert_selector ".card", text: "Global Filters:"

    # === STEP 3: Test clearing global filters ===
    # Clear filters from jobs page
    clear_global_filters

    # Verify filters removed
    assert_global_filters_inactive
    assert_selector "table tbody tr", wait: 5

    # Navigate to routes page and verify filters cleared (routes has time range dropdown)
    visit_rails_pulse_path "/routes"

    assert_dropdown_visible # Should show dropdown, not custom picker
    assert_global_filters_inactive

    # Default "Last 24 hours" should be selected
    dropdown_value = find("select[name='q[period_start_range]']").value

    assert_equal "last_day", dropdown_value, "Dropdown should show default 'Last 24 hours' after clearing"

    # === STEP 4: Test page-specific filters work independently ===
    # Set a new global filter
    global_start = 1.month.ago.strftime("%Y-%m-%d %H:%M")
    global_end = Time.current.strftime("%Y-%m-%d %H:%M")

    set_global_filters(date_range: "#{global_start} to #{global_end}")

    # Verify global filter applied
    assert_custom_picker_visible
    assert_global_filters_active

    visit_rails_pulse_path "/jobs"

    assert_global_filters_active
    assert_selector ".card", text: "Global Filters:"

    # Now override with page-specific preset by navigating to a URL with preset parameter
    # This simulates selecting "Last 24 hours" from the dropdown
    visit_rails_pulse_path "/routes?q[period_start_range]=last_day"

    # Page-specific filter should override global filter
    assert_dropdown_visible # Dropdown shown (not custom picker)

    current_selection = find("select[name='q[period_start_range]']").value

    assert_equal "last_day", current_selection, "Page-specific preset should override global filter"

    # But global filter icon should still show as active
    assert_global_filters_active

    # === STEP 5: Verify global filter modal shows current values ===
    # Set both date range and performance threshold
    visit_rails_pulse_path "/routes"

    recent_start = 3.days.ago.strftime("%Y-%m-%d %H:%M")
    recent_end = Time.current.strftime("%Y-%m-%d %H:%M")

    set_global_filters(
      date_range: "#{recent_start} to #{recent_end}",
      threshold: "All Requests"
    )

    # Verify both filters applied
    assert_global_filters_active
    assert_custom_picker_visible

    # Navigate to another page and verify both filters persist
    visit_rails_pulse_path "/requests"

    assert_custom_picker_visible
    assert_selector "table tbody tr", wait: 5

    visit_rails_pulse_path "/jobs/#{@report_job.id}"

    assert_selector "table tbody tr", wait: 5

    # === STEP 6: Clear all global filters and verify clean state ===
    clear_global_filters

    assert_global_filters_inactive
    assert_dropdown_visible

    # Verify we're back to default state across all pages
    visit_rails_pulse_path "/routes"

    assert_dropdown_visible
    assert_global_filters_inactive

    visit_rails_pulse_path "/queries"

    assert_dropdown_visible
    assert_global_filters_inactive
  end

  test "tag filters complete workflow" do
    # Fixture data includes:
    # Routes with tags: api_users ["api", "users"], api_posts ["api", "posts"],
    #                   api_test ["api"], api_cleanup ["maintenance"], api_other []
    # Queries with tags: simple_query ["database", "users"], complex_query ["database", "posts"],
    #                    analyzed_query ["database"], stale_analyzed_query [], query_with_issues ["critical"]

    # === STEP 1: Visit routes page and verify all routes visible initially ===
    visit_rails_pulse_path "/routes"

    # Should see routes with different tags
    assert_selector "table tbody tr", minimum: 1, wait: 5

    # === STEP 2: Disable "api" tag and verify filtering on routes page ===
    toggle_tag_filter("api")

    # Global filter should be active
    assert_global_filters_active

    # Verify "api" tag is now disabled
    assert_tag_disabled("api")

    # Routes with "api" tag should be filtered out
    # (api_users, api_posts, api_test all have "api" tag)
    # Only api_cleanup with "maintenance" tag should show (if it has summaries)

    # === STEP 3: Verify tag filters persist across pages ===
    visit_rails_pulse_path "/queries"

    # Global filter should still be active
    assert_global_filters_active

    # Verify "api" tag still disabled
    assert_tag_disabled("api")

    # === STEP 4: Disable "database" tag on queries page ===
    toggle_tag_filter("database")

    # Queries with "database" tag should be filtered out
    # (simple_query, complex_query, analyzed_query all have "database" tag)
    # Only stale_analyzed_query and query_with_issues should potentially show

    # === STEP 5: Test "non_tagged" virtual tag ===
    # Disable the "non_tagged" filter to hide items without tags
    toggle_tag_filter("non_tagged")

    # Now items without tags should be hidden
    assert_tag_disabled("non_tagged")

    # === STEP 6: Navigate to routes and verify both tag filters active ===
    visit_rails_pulse_path "/routes"

    assert_global_filters_active
    assert_tag_disabled("api")
    assert_tag_disabled("non_tagged")

    # === STEP 7: Re-enable "api" tag ===
    toggle_tag_filter("api")

    # "api" tag should now be enabled again
    assert_tag_enabled("api")

    # But "non_tagged" should still be disabled
    assert_tag_disabled("non_tagged")

    # === STEP 8: Clear all filters ===
    clear_global_filters

    # All tags should be enabled again
    assert_global_filters_inactive

    # Verify all tags are back to enabled state
    assert_tag_enabled("api")
    assert_tag_enabled("database")
    assert_tag_enabled("non_tagged")

    # === STEP 9: Verify clean state across pages ===
    visit_rails_pulse_path "/queries"

    assert_global_filters_inactive
    assert_tag_enabled("database")

    visit_rails_pulse_path "/routes"

    assert_global_filters_inactive
    assert_tag_enabled("api")
  end

  private

  def create_comprehensive_test_data
    # Create requests with various performance levels at different times
    # This data ensures we have rows to display regardless of filters

    # Recent data (1 hour ago) - ensures "Last 24 hours" shows data
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

    # Mid-range data (3 days ago) - within "Last Week" and our test date ranges
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

    # Older data (1 week ago) - for testing longer date ranges
    RailsPulse::Request.create!(
      route: route_slow,
      duration: 1800.0,
      occurred_at: 1.week.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-global-veryslow-1",
      controller_action: "Api::UsersController#index"
    )

    # Very old data (2 weeks ago) - for testing month-long ranges
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

    # Generate summaries for the test data so charts and aggregates work
    RailsPulse::SummaryService.new("hour", 1.hour.ago.beginning_of_hour).perform
    RailsPulse::SummaryService.new("day", 3.days.ago.beginning_of_day).perform
    RailsPulse::SummaryService.new("day", 1.week.ago.beginning_of_day).perform
    RailsPulse::SummaryService.new("day", 2.weeks.ago.beginning_of_day).perform
  end
end
