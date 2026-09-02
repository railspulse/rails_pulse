module GlobalFiltersHelpers
  def open_global_filters_modal
    find('[data-action*="global-filters#open"]').click

    assert_selector ".dialog__content", wait: 3
  end

  def set_global_performance_threshold(threshold)
    open_global_filters_modal

    within(".dialog__content") do
      assert_selector "input[type='submit'][value='Apply Filters']", wait: 5
      select threshold, from: "performance_threshold"
    end

    # Click submit outside the within scope — clicking inside causes Capybara to
    # synchronize against the stale dialog scope after the page navigation.
    find(".dialog__content input[type='submit'][value='Apply Filters']").click
  end

  def clear_global_filters
    open_global_filters_modal

    assert_selector ".dialog__content button[type='submit']", text: "Clear", wait: 5
    find(".dialog__content button[type='submit']", text: "Clear").click

    assert_no_selector ".dialog__content", wait: 5
    assert_selector '[data-action*="global-filters#open"]', wait: 5
  end

  def assert_global_filters_active
    # Use assert_selector so Capybara finds and checks atomically with retry,
    # avoiding stale element errors from holding a reference across DOM updates.
    assert_selector '[data-rails-pulse--global-filters-target="indicator"] svg', wait: 3
  end

  def assert_global_filters_inactive
    # Check for list-filter icon (inactive state)
    assert_selector '[data-rails-pulse--global-filters-target="indicator"]'
  end

  def select_custom_date_range(start_date, end_date)
    # Click the time range trigger button to open the popover
    find(".time-range-trigger").click

    # Wait for popover menu to appear
    assert_selector '[data-rails-pulse--popover-target="menu"]', visible: true, wait: 3

    # Click "Custom Range..." button to open the modal
    find("button", text: "Custom Range...").click

    # Wait for modal to appear
    assert_selector '[data-rails-pulse--time-range-target="modalWrapper"]', visible: true, wait: 3

    # Wait for flatpickr to initialize
    sleep 0.5

    # Set the date range using flatpickr API on the date input
    page.execute_script(<<~JS)
      var dateInput = document.querySelector('[data-rails-pulse--time-range-target="dateInput"]');
      if (dateInput && dateInput._flatpickr) {
        dateInput._flatpickr.setDate(['#{start_date}', '#{end_date}'], true);
      }
    JS

    sleep 0.3

    # Click Apply button to apply the custom range
    within('[data-rails-pulse--time-range-target="modal"]') do
      click_button "Apply"
    end

    # Wait for modal to close
    assert_no_selector '[data-rails-pulse--time-range-target="modalWrapper"]', visible: true, wait: 3
  end

  def assert_custom_picker_visible
    assert_selector '[data-rails-pulse--time-range-target="modalWrapper"]', visible: true, wait: 5
  end

  def assert_time_range_label(expected_text)
    # Use a waiting matcher: after switching ranges the page reloads, and a
    # one-shot find + text comparison races the old page's label.
    assert_selector '[data-rails-pulse--time-range-target="label"]', text: expected_text, wait: 5
  end

  def close_custom_range_modal
    within('[data-rails-pulse--time-range-target="modal"]') do
      # Click the Cancel button (not the X button)
      click_button "Cancel"
    end

    assert_no_selector '[data-rails-pulse--time-range-target="modalWrapper"]', visible: true, wait: 3
  end

  # Tag filtering helpers
  def toggle_tag_filter(tag_name)
    open_global_filters_modal

    checkbox_id = "tag_#{tag_name.parameterize.underscore}"
    checkbox = find(".dialog__content ##{checkbox_id}")
    checkbox.click

    submit = find(".dialog__content input[type='submit'][value='Apply Filters']")
    submit.click

    assert_no_selector ".dialog__content", wait: 5
    assert_selector '[data-action*="global-filters#open"]', wait: 5
  end

  def assert_tag_enabled(tag_name)
    open_global_filters_modal

    checkbox_id = "tag_#{tag_name.parameterize.underscore}"
    checkbox = find(".dialog__content ##{checkbox_id}")

    assert_predicate checkbox, :checked?, "Expected tag '#{tag_name}' to be enabled"

    find('.dialog__content a[aria-label="Close"]').click

    assert_no_selector ".dialog__content", wait: 3
  end

  def assert_tag_disabled(tag_name)
    open_global_filters_modal

    checkbox_id = "tag_#{tag_name.parameterize.underscore}"
    checkbox = find(".dialog__content ##{checkbox_id}")

    assert_not checkbox.checked?, "Expected tag '#{tag_name}' to be disabled"

    find('.dialog__content a[aria-label="Close"]').click

    assert_no_selector ".dialog__content", wait: 3
  end
end
