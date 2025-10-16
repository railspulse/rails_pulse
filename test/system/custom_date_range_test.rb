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

  test "custom date range picker complete workflow" do
    skip "Skipping in CI due to timing issues with flatpickr" if ENV["CI"]

    visit_rails_pulse_path "/routes"

    # === STEP 1: Verify initial state ===
    # When page loads, dropdown should be visible (not custom picker)
    assert_dropdown_visible

    # === STEP 2: Select "Custom Range..." option ===
    # This should hide the dropdown and show the custom picker
    select "Custom Range...", from: "q[period_start_range]"

    # Verify UI swapped correctly
    assert_custom_picker_visible

    # Verify datepicker is configured to show 2 months
    assert_selector 'input[data-rails-pulse--datepicker-show-months-value="2"]', visible: false

    # Verify close button (X) is visible
    assert_selector '[data-action*="custom-range#showSelect"]', visible: true

    # Verify flatpickr calendar auto-opens
    assert_selector ".flatpickr-calendar.open", visible: true, wait: 2

    # Verify the flatpickr input is present and visible
    assert_selector 'input[placeholder*="Pick date range"]', visible: true

    # === STEP 3: Select a custom date range and submit ===
    # Pick dates that will match our test data (1 day ago to now)
    start_date = "2025-10-14 14:08"
    end_date = "2025-10-15 16:30"

    # Wait for flatpickr to initialize
    sleep 0.5

    # Use flatpickr API to set the date range (simulates user selecting dates from calendar)
    # This directly sets the dates without needing to interact with the dropdown
    page.execute_script(<<~JS)
      var hiddenInput = document.querySelector('input[name="q[custom_date_range]"]');
      if (hiddenInput && hiddenInput._flatpickr) {
        hiddenInput._flatpickr.setDate(['#{start_date}', '#{end_date}'], true);
        // Close the flatpickr to ensure all change events have fired
        hiddenInput._flatpickr.close();
      }
    JS

    # Wait for flatpickr to close and all change events to complete
    assert_no_selector ".flatpickr-calendar.open", wait: 3

    # Verify the hidden input has a value before submitting
    hidden_input_value = find('input[name="q[custom_date_range]"]', visible: :all).value

    assert_predicate hidden_input_value, :present?, "Hidden input should have a value before form submission"
    assert_includes hidden_input_value, " to ", "Hidden input should contain date range with ' to ' separator"

    # Add extra delay for CI to ensure all event handlers and DOM mutations complete
    sleep 1

    # Submit the form
    click_button "Search"

    # Verify results are shown
    assert_selector "table tbody tr", wait: 5

    # === STEP 4: Verify custom range persists in URL ===
    # URL should contain the custom_date_range parameter
    assert_includes page.current_url, "custom_date_range", "URL should contain custom_date_range parameter"

    # Custom picker should still be visible (not dropdown)
    assert_custom_picker_visible

    # === STEP 5: Test persistence on page reload ===
    # Save current URL and reload the page
    current_url = page.current_url
    visit current_url

    # After reload, custom picker should still be visible
    assert_custom_picker_visible

    # URL should still have custom_date_range parameter
    assert_includes page.current_url, "custom_date_range"

    # Data should still be filtered
    assert_selector "table tbody tr", wait: 5

    # === STEP 6: Test closing custom picker ===
    # Click the X button to close custom picker and show dropdown again
    close_custom_range_picker

    # Dropdown should now be visible
    assert_dropdown_visible

    # Dropdown should reset to default value (Last 24 hours)
    dropdown_value = find("select[name='q[period_start_range]']").value

    assert_equal "last_day", dropdown_value, "Dropdown should reset to 'Last 24 hours' default"

    # === STEP 7: Test switching to a preset range ===
    # Navigate to a preset range (simulates selecting "Last Week" from dropdown)
    visit_rails_pulse_path "/routes?q[period_start_range]=last_week"

    # Verify results are shown
    assert_selector "table tbody tr", wait: 5

    # URL should have the preset parameter (check for both encoded and unencoded versions)
    assert page.current_url.include?("period_start_range]=last_week") || page.current_url.include?("period_start_range%5D=last_week"),
      "URL should have last_week preset. Got: #{page.current_url}"

    # URL should NOT have custom_date_range with a value
    refute_match(/custom_date_range[=%\]][^&]+/, page.current_url,
      "URL should NOT have custom_date_range with a value. Got: #{page.current_url}")

    # Dropdown should be visible (not custom picker)
    assert_dropdown_visible

    # Dropdown should show "Last Week"
    dropdown_value_final = find("select[name='q[period_start_range]']").value

    assert_equal "last_week", dropdown_value_final, "Dropdown should show last_week"

    # === STEP 8: Test UI updates with different date ranges ===
    # Verify the custom picker can be used multiple times with different dates
    visit_rails_pulse_path "/routes"

    # Select "Custom Range..." to show the picker
    select "Custom Range...", from: "q[period_start_range]"

    assert_custom_picker_visible

    # Set older date range to verify the UI updates
    start_date_old = 10.days.ago.strftime("%Y-%m-%d %H:%M")
    end_date_old = 3.days.ago.strftime("%Y-%m-%d %H:%M")

    sleep 0.5

    page.execute_script(<<~JS)
      var hiddenInput = document.querySelector('input[name="q[custom_date_range]"]');
      if (hiddenInput && hiddenInput._flatpickr) {
        hiddenInput._flatpickr.setDate(['#{start_date_old}', '#{end_date_old}'], true);
      }
    JS

    sleep 0.3

    # Verify the visible input shows the updated date range
    # The flatpickr alt input should display the formatted dates
    date_display = find('input[placeholder*="Pick date range"]').value

    assert_predicate date_display, :present?, "Date picker should show selected dates"

    # Verify the hidden input has the correct value format
    hidden_value = find('input[name="q[custom_date_range]"]', visible: :all).value

    assert_includes hidden_value, " to ", "Hidden input should contain date range in 'start to end' format"

    # Custom picker should still be visible
    assert_custom_picker_visible
  end

  private

  def create_comprehensive_test_data
    # Create requests at various dates for date range filtering
    # This ensures we have data that matches the different date ranges tested above

    # Recent data (1-2 days ago) - matches default "Last 24 hours" and recent custom ranges
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

    # Mid-range data (5-7 days ago) - matches "Last Week" preset
    RailsPulse::Request.create!(
      route: route,
      duration: 300.0,
      occurred_at: 6.days.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-custom-range-mid-1",
      controller_action: "Api::TestController#index"
    )

    # Older data (10-14 days ago) - matches older custom date ranges
    RailsPulse::Request.create!(
      route: route,
      duration: 400.0,
      occurred_at: 12.days.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-custom-range-old-1",
      controller_action: "Api::TestController#index"
    )

    # Generate summaries for the test data
    # Summaries are used for chart data and aggregate metrics
    RailsPulse::SummaryService.new("day", 1.day.ago.beginning_of_day).perform
    RailsPulse::SummaryService.new("day", 6.days.ago.beginning_of_day).perform
    RailsPulse::SummaryService.new("day", 12.days.ago.beginning_of_day).perform
  end
end
