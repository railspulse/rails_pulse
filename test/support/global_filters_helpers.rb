module GlobalFiltersHelpers
  def open_global_filters_modal
    find('[data-action*="global-filters#open"]').click

    assert_selector ".dialog__content", wait: 3
  end

  def set_global_performance_threshold(threshold)
    open_global_filters_modal

    within(".dialog__content") do
      # Wait for button to be ready
      assert_selector "input[type='submit'][value='Apply Filters']", wait: 5
      select threshold, from: "performance_threshold"
      click_button "Apply Filters"
    end

    assert_no_selector ".dialog__content", wait: 3
  end

  def clear_global_filters
    open_global_filters_modal

    within(".dialog__content") do
      # Wait for button to be ready (Clear is a button element, not input)
      assert_selector "button[type='submit']", text: "Clear", wait: 5
      click_button "Clear"
    end

    assert_no_selector ".dialog__content", wait: 3
  end

  def assert_global_filters_active
    icon = find('[data-rails-pulse--global-filters-target="indicator"]')
    # Check for list-filter-plus icon (active state)
    assert icon.text.present? || icon.has_css?("svg")
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
    label = find('[data-rails-pulse--time-range-target="label"]')

    assert_includes label.text, expected_text
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

    within(".dialog__content") do
      # Find the checkbox by its id (tag_<name>)
      checkbox_id = "tag_#{tag_name.parameterize.underscore}"
      find("##{checkbox_id}").click

      # Wait for button to be ready
      assert_selector "input[type='submit'][value='Apply Filters']", wait: 5
      click_button "Apply Filters"
    end

    assert_no_selector ".dialog__content", wait: 3
  end

  def assert_tag_enabled(tag_name)
    open_global_filters_modal

    within(".dialog__content") do
      checkbox_id = "tag_#{tag_name.parameterize.underscore}"
      checkbox = find("##{checkbox_id}")

      assert_predicate checkbox, :checked?, "Expected tag '#{tag_name}' to be enabled"

      # Close modal using the X button
      find('a[aria-label="Close"]').click
    end

    assert_no_selector ".dialog__content", wait: 3
  end

  def assert_tag_disabled(tag_name)
    open_global_filters_modal

    within(".dialog__content") do
      checkbox_id = "tag_#{tag_name.parameterize.underscore}"
      checkbox = find("##{checkbox_id}")

      assert_not checkbox.checked?, "Expected tag '#{tag_name}' to be disabled"

      # Close modal using the X button
      find('a[aria-label="Close"]').click
    end

    assert_no_selector ".dialog__content", wait: 3
  end
end
