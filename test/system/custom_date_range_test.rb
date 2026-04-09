require "test_helper"
require_relative "../support/global_filters_helpers"

class CustomDateRangeTest < ApplicationSystemTestCase
  include GlobalFiltersHelpers

  def setup
    super
    # Fixtures are automatically loaded
  end

  test "custom date range picker complete workflow" do
    visit_rails_pulse_path "/routes"

    # Wait for page to fully load
    assert_selector "body", wait: 5
    sleep 0.5

    # === STEP 1: Verify time range selector is visible ===
    assert_selector ".time-range-trigger", visible: true

    # === STEP 2: Open custom date range modal ===
    # Click the time range trigger to open popover
    find(".time-range-trigger").click

    assert_selector '[data-rails-pulse--popover-target="menu"]', visible: true, wait: 3

    # Click "Custom Range..." to open modal
    find("button", text: "Custom Range...").click

    # Verify modal appears
    assert_custom_picker_visible

    # Verify datepicker is configured to show 2 months (hidden input element)
    assert_selector '[data-rails-pulse--datepicker-show-months-value="2"]', visible: :all, wait: 3

    # Verify close button (X) is visible
    assert_selector '[data-action*="time-range#cancelCustom"]', visible: true

    # === STEP 3: Set custom date range ===
    start_date = 2.days.ago.strftime("%Y-%m-%d %H:%M")
    end_date = Time.current.strftime("%Y-%m-%d %H:%M")

    # Wait for flatpickr to initialize
    sleep 0.5

    # Set the date range using flatpickr API
    page.execute_script(<<~JS)
      var dateInput = document.querySelector('[data-rails-pulse--time-range-target="dateInput"]');
      if (dateInput && dateInput._flatpickr) {
        dateInput._flatpickr.setDate(['#{start_date}', '#{end_date}'], true);
      }
    JS

    sleep 0.3

    # Verify the date input has a value (wait for it to be available)
    date_input_value = find('[data-rails-pulse--time-range-target="dateInput"]', visible: :all, wait: 5).value

    assert_predicate date_input_value, :present?, "Date input should have a value"

    # === STEP 4: Apply custom range ===
    within('[data-rails-pulse--time-range-target="modal"]') do
      click_button "Apply"
    end

    # Modal should close
    assert_no_selector '[data-rails-pulse--time-range-target="modalWrapper"]', visible: true, wait: 3

    # Wait for page to reload with custom range
    assert_selector "table", wait: 5

    # === STEP 5: Verify custom range was applied ===
    # The time range trigger should show the custom date range in its label
    label_text = find('[data-rails-pulse--time-range-target="label"]').text

    assert_predicate label_text, :present?, "Time range label should show custom dates"

    # Verify we have data displayed
    assert_selector "table tbody tr", minimum: 1, wait: 3

    # === STEP 6: Test canceling custom range modal ===
    # Open the modal again
    find(".time-range-trigger").click

    assert_selector '[data-rails-pulse--popover-target="menu"]', visible: true, wait: 3
    find("button", text: "Custom Range...").click

    assert_custom_picker_visible

    # Click cancel button
    close_custom_range_modal

    # Modal should be closed
    assert_no_selector '[data-rails-pulse--time-range-target="modalWrapper"]', visible: true

    # === STEP 7: Test switching to a preset range ===
    # Open time range selector
    find(".time-range-trigger").click

    assert_selector '[data-rails-pulse--popover-target="menu"]', visible: true, wait: 3

    # Select "Last 7 days" preset
    find('button[data-preset="last_7_days"]').click

    # Wait for page to reload
    assert_selector "table", wait: 5

    # Verify label updated to show "Last 7 days"
    assert_time_range_label "Last 7 days"

    # === STEP 8: Test persistence across pages ===
    # The time range should persist when navigating to another page
    visit_rails_pulse_path "/queries"

    # Wait for page load
    assert_selector "body", wait: 5
    sleep 0.5

    # Time range label should still show "Last 7 days"
    assert_time_range_label "Last 7 days"

    # === STEP 9: Set another custom range ===
    start_date_new = 10.days.ago.strftime("%Y-%m-%d %H:%M")
    end_date_new = 3.days.ago.strftime("%Y-%m-%d %H:%M")

    find(".time-range-trigger").click

    assert_selector '[data-rails-pulse--popover-target="menu"]', visible: true, wait: 3
    find("button", text: "Custom Range...").click

    assert_custom_picker_visible

    sleep 0.5

    page.execute_script(<<~JS)
      var dateInput = document.querySelector('[data-rails-pulse--time-range-target="dateInput"]');
      if (dateInput && dateInput._flatpickr) {
        dateInput._flatpickr.setDate(['#{start_date_new}', '#{end_date_new}'], true);
      }
    JS

    sleep 0.3

    within('[data-rails-pulse--time-range-target="modal"]') do
      click_button "Apply"
    end

    assert_no_selector '[data-rails-pulse--time-range-target="modalWrapper"]', visible: true, wait: 3

    # Verify custom range label is displayed
    label_text_final = find('[data-rails-pulse--time-range-target="label"]').text

    assert_predicate label_text_final, :present?, "Time range label should show new custom dates"
  end
end
