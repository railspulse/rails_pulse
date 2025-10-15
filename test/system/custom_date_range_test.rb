require "test_helper"
require_relative "../support/shared_test_data"
require_relative "../support/global_filters_helpers"

class CustomDateRangeTest < ApplicationSystemTestCase
  include SharedTestData
  include GlobalFiltersHelpers

  def setup
    super
    load_shared_test_data
    create_comprehensive_test_data
  end

  test "custom range option shows datepicker" do
    visit_rails_pulse_path "/routes"

    # Initial state: dropdown should be visible
    assert_dropdown_visible

    # Select "Custom Range..."
    select "Custom Range...", from: "q[period_start_range]"

    # Verify UI swaps
    assert_custom_picker_visible

    # Verify datepicker shows 2 months (configured via data attribute)
    assert_selector 'input[data-rails-pulse--datepicker-show-months-value="2"]', visible: false

    # Verify close button is visible
    assert_selector '[data-action*="custom-range#showSelect"]', visible: true
  end

  test "custom range picker auto opens calendar" do
    visit_rails_pulse_path "/routes"

    # Select "Custom Range..."
    select "Custom Range...", from: "q[period_start_range]"

    # Verify flatpickr calendar auto-opens and is visible in DOM
    assert_selector ".flatpickr-calendar.open", visible: true, wait: 2
  end

  test "selecting custom date range shows picker" do
    visit_rails_pulse_path "/routes"

    # Select "Custom Range..." from dropdown
    select "Custom Range...", from: "q[period_start_range]"

    # Verify custom picker appears
    assert_custom_picker_visible

    # Verify the flatpickr input is present
    assert_selector 'input[placeholder*="Pick date range"]', visible: true

    # Note: Testing actual date selection and form submission with flatpickr
    # is difficult without JavaScript manipulation. This test verifies the
    # UI components are present and the picker is shown correctly.
  end

  test "custom range works and persists after submission" do
    visit_rails_pulse_path "/routes"

    # Select custom range
    start_date = "2025-10-14 14:08"
    end_date = "2025-10-15 16:30"

    select_custom_date_range(start_date, end_date)

    # Submit and verify the custom range works
    click_button "Search"

    assert_selector "table tbody tr", wait: 5

    # Verify URL contains custom date range parameter
    assert_includes page.current_url, "custom_date_range"

    # Verify custom picker is still visible after page reload
    assert_custom_picker_visible
  end

  test "switching back to preset from custom range" do
    visit_rails_pulse_path "/routes"

    # Select custom range and pick dates
    start_date = 7.days.ago.strftime("%Y-%m-%d %H:%M")
    end_date = Time.current.strftime("%Y-%m-%d %H:%M")

    select_custom_date_range(start_date, end_date)
    click_button "Search"

    assert_selector "table tbody tr", wait: 5

    # Verify custom picker is visible
    assert_custom_picker_visible

    # Click X button to close custom range
    close_custom_range_picker

    # Verify dropdown is back and shows default
    assert_dropdown_visible

    dropdown_value = find("select[name='q[period_start_range]']").value

    assert_equal "last_day", dropdown_value, "Dropdown should reset to 'Last 24 hours' default"

    # Now instead of trying to submit the form with a changed dropdown value,
    # let's just navigate to a fresh page with the Last Week preset
    # This simulates the user clicking a preset after closing custom range
    visit_rails_pulse_path "/routes?q[period_start_range]=last_week"

    assert_selector "table tbody tr", wait: 5

    # Verify URL uses preset, not custom range
    current_url = page.current_url

    # URL should contain period_start_range with last_week value
    assert_match(/period_start_range[=%]last_week/, current_url, "URL should have last_week preset")

    # URL should NOT contain custom_date_range with a value
    refute_match(/custom_date_range[=%][^&]+/, current_url, "URL should NOT have custom_date_range with a value")

    # Verify dropdown is visible (not custom picker) and shows Last Week
    assert_dropdown_visible

    dropdown_value_final = find("select[name='q[period_start_range]']").value
    assert_equal "last_week", dropdown_value_final, "Dropdown should show last_week"
  end

  test "custom range persists on page reload" do
    visit_rails_pulse_path "/routes"

    # Select custom range
    start_date = 10.days.ago.strftime("%Y-%m-%d %H:%M")
    end_date = 3.days.ago.strftime("%Y-%m-%d %H:%M")

    select_custom_date_range(start_date, end_date)
    click_button "Search"

    assert_selector "table tbody tr", wait: 5

    # Verify URL contains custom_date_range parameter
    current_url = page.current_url

    assert_includes current_url, "custom_date_range", "URL should contain custom_date_range after submission"

    # Verify custom picker visible after submission
    assert_custom_picker_visible

    # Reload page by visiting same URL
    visit current_url

    assert_selector "table tbody tr", wait: 5

    # Verify custom picker still visible after reload
    assert_custom_picker_visible

    # Verify URL still has custom_date_range
    assert_includes page.current_url, "custom_date_range"
  end

  test "global date range populates custom picker" do
    # Set global date range
    global_start = 7.days.ago.strftime("%b %d, %Y %l:%M %p")
    global_end = Time.current.strftime("%b %d, %Y %l:%M %p")
    global_range = "#{global_start} to #{global_end}"

    visit_rails_pulse_path "/routes"

    set_global_date_range(global_start, global_end)

    # Verify redirected to routes page
    assert_current_path "/rails_pulse/routes"

    # Verify custom picker is visible (not dropdown)
    assert_custom_picker_visible

    # Verify period_start_range is set to "custom" by checking the hidden select
    select_element = find('select[name="q[period_start_range]"]', visible: :all)

    assert_equal "custom", select_element.value, "period_start_range should be 'custom' when global filter is set"

    # Verify custom date input shows global date range
    date_input_value = find('input[placeholder*="Pick date range"]').value

    assert_predicate date_input_value, :present?, "Custom date input should show global date range"

    # Verify table is filtered to global range
    assert_selector "table tbody tr", wait: 5

    # Verify user can modify dates (override global range)
    new_start = 3.days.ago.strftime("%Y-%m-%d %H:%M")
    new_end = Time.current.strftime("%Y-%m-%d %H:%M")

    # Update the date range input directly
    date_range_input = find('input[placeholder*="Pick date range"]')
    date_range_input.set("#{new_start} to #{new_end}")

    sleep 0.3
    click_button "Search"

    assert_selector "table tbody tr", wait: 5

    # Verify URL now has page-specific custom range (overriding global)
    assert_includes page.current_url, "custom_date_range"
  end

  private

  def create_comprehensive_test_data
    # Create requests at various dates for date range filtering

    # Recent data (1-2 days ago)
    route = rails_pulse_routes(:api_test)
    RailsPulse::Request.create!(
      route: route,
      duration: 200.0,
      occurred_at: 1.day.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-custom-range-recent-1",
      controller_action: "Api::TestController#index"
    )

    # Mid-range data (5-7 days ago)
    RailsPulse::Request.create!(
      route: route,
      duration: 300.0,
      occurred_at: 6.days.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-custom-range-mid-1",
      controller_action: "Api::TestController#index"
    )

    # Older data (10-14 days ago)
    RailsPulse::Request.create!(
      route: route,
      duration: 400.0,
      occurred_at: 12.days.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-custom-range-old-1",
      controller_action: "Api::TestController#index"
    )

    # Generate summaries
    RailsPulse::SummaryService.new("day", 1.day.ago.beginning_of_day).perform
    RailsPulse::SummaryService.new("day", 6.days.ago.beginning_of_day).perform
    RailsPulse::SummaryService.new("day", 12.days.ago.beginning_of_day).perform
  end
end
