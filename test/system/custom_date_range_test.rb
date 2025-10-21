require "test_helper"
require_relative "../support/global_filters_helpers"

class CustomDateRangeTest < ApplicationSystemTestCase
  include GlobalFiltersHelpers

  def setup
    super
    # Fixtures are automatically loaded
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

    # Wait for flatpickr to be fully initialized and auto-opened
    # (The custom_range_controller automatically opens the calendar with a 50ms delay)
    assert_selector ".flatpickr-calendar.open", visible: true, wait: 2

    # === STEP 3: Select a custom date range and submit ===
    # Pick dates that will match our fixture data (custom_range_recent is 1 day ago)
    start_date = 2.days.ago.strftime("%Y-%m-%d %H:%M")
    end_date = Time.current.strftime("%Y-%m-%d %H:%M")

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

    # Verify that period_start_range is set to 'custom'
    period_range_value = find('select[name="q[period_start_range]"]', visible: :all).value

    assert_equal "custom", period_range_value, "period_start_range should be 'custom' when using custom date picker"

    # Add extra delay for CI to ensure all event handlers and DOM mutations complete
    sleep 1

    # Submit the form
    click_button "Search"

    # Wait for page navigation to complete
    assert_selector "table", wait: 5

    # === STEP 4: Verify custom range was applied ===
    # The custom date range picker should still be visible with the selected dates
    assert_custom_picker_visible

    # Verify the date range is still displayed in the picker
    displayed_dates = find('input[placeholder*="Pick date range"]').value

    assert_predicate displayed_dates, :present?, "Custom date picker should show selected date range"

    # Verify we have results (the fixture data should match our date range)
    assert_selector "table tbody tr", minimum: 1, wait: 3

    # === STEP 5: Test that custom picker can be closed ===
    # (Skip URL persistence test as custom date ranges may not persist in URL)

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
end
