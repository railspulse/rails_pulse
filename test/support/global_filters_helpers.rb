module GlobalFiltersHelpers
  def open_global_filters_modal
    find('[data-action*="global-filters#open"]').click

    assert_selector ".dialog__content", wait: 3
  end

  def set_global_date_range(start_date, end_date)
    open_global_filters_modal

    # Wait for flatpickr to initialize
    sleep 0.5

    # Set the date range using flatpickr API (similar to custom range)
    page.execute_script(<<~JS)
      var hiddenInput = document.querySelector('input[name="date_range"]');
      if (hiddenInput && hiddenInput._flatpickr) {
        hiddenInput._flatpickr.setDate(['#{start_date}', '#{end_date}'], true);
      }
    JS

    sleep 0.3

    within(".dialog__content") do
      click_button "Apply Filters"
    end

    assert_no_selector ".dialog__content", wait: 3
  end

  def set_global_performance_threshold(threshold)
    open_global_filters_modal

    within(".dialog__content") do
      select threshold, from: "performance_threshold"
      click_button "Apply Filters"
    end

    assert_no_selector ".dialog__content", wait: 3
  end

  def set_global_filters(date_range: nil, threshold: nil)
    open_global_filters_modal

    # Wait for flatpickr to initialize if date range is being set
    sleep 0.5 if date_range

    # Set date range using flatpickr API if provided
    if date_range
      # Parse the date range string "Start to End" and convert to array for flatpickr
      if date_range.include?(" to ")
        dates = date_range.split(" to ").map(&:strip)
        page.execute_script(<<~JS)
          var hiddenInput = document.querySelector('input[name="date_range"]');
          if (hiddenInput && hiddenInput._flatpickr) {
            hiddenInput._flatpickr.setDate(['#{dates[0]}', '#{dates[1]}'], true);
          }
        JS
      else
        page.execute_script(<<~JS)
          var hiddenInput = document.querySelector('input[name="date_range"]');
          if (hiddenInput && hiddenInput._flatpickr) {
            hiddenInput._flatpickr.setDate('#{date_range}', true);
          }
        JS
      end

      sleep 1 # Give more time for flatpickr to process and update
    end

    # Wait for modal to be fully visible
    within(".dialog__content") do
      select threshold, from: "performance_threshold" if threshold
      click_button "Apply Filters"
    end

    assert_no_selector ".dialog__content", wait: 3
  end

  def clear_global_filters
    open_global_filters_modal

    within(".dialog__content") do
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
    select "Custom Range...", from: "q[period_start_range]"

    # Wait for custom picker to appear
    assert_selector '[data-rails-pulse--custom-range-target="pickerWrapper"]', visible: true, wait: 2

    # Wait for flatpickr to initialize
    sleep 0.5

    # Find the hidden input with flatpickr instance and set the date range
    # The setDate method with second param 'true' triggers change events
    # which updates both the hidden input (form value) and alt input (display)
    page.execute_script(<<~JS)
      var hiddenInput = document.querySelector('input[name="q[custom_date_range]"]');
      if (hiddenInput && hiddenInput._flatpickr) {
        hiddenInput._flatpickr.setDate(['#{start_date}', '#{end_date}'], true);
      }
    JS

    sleep 0.3
  end

  def assert_custom_picker_visible
    assert_selector '[data-rails-pulse--custom-range-target="pickerWrapper"]', visible: true, wait: 3
    assert_selector '[data-rails-pulse--custom-range-target="selectWrapper"]', visible: false
  end

  def assert_dropdown_visible
    assert_selector '[data-rails-pulse--custom-range-target="selectWrapper"]', visible: true
    assert_selector '[data-rails-pulse--custom-range-target="pickerWrapper"]', visible: false
  end

  def close_custom_range_picker
    find('[data-action*="custom-range#showSelect"]').click

    assert_dropdown_visible
  end

  # Tag filtering helpers
  def toggle_tag_filter(tag_name)
    open_global_filters_modal

    within(".dialog__content") do
      # Find the checkbox by its id (tag_<name>)
      checkbox_id = "tag_#{tag_name.parameterize.underscore}"
      find("##{checkbox_id}").click
    end

    within(".dialog__content") do
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
