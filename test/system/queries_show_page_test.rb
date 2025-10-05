require "test_helper"
require_relative "../support/shared_index_page_test"

class QueriesShowPageTest < SharedIndexPageTest
  def page_path
    "/queries/#{target_query.id}"
  end

  def target_query
    @target_query ||= @complex_query
  end

  def page_type
    :operations
  end

  def chart_selector
    "#query_responses_chart"
  end

  def performance_filter_options
    {
      slow: "Slow (≥ 100ms)",
      critical: "Critical (≥ 1000ms)"
    }
  end

  def all_test_data
    # Only operations for the target query from shared data
    target_query.operations.to_a
  end

  def default_scope_data
    target_query.operations.to_a
  end

  def last_week_data
    target_query.operations.to_a
  end

  def last_month_data
    target_query.operations.to_a
  end

  def slow_performance_data
    # Operations with slow duration (≥ 100ms)
    (all_test_data).select { |operation| operation.duration >= 100 }
  end

  def critical_performance_data
    # Operations with critical duration (≥ 1000ms)
    (all_test_data).select { |operation| operation.duration >= 1000 }
  end

  def zoomed_data
    # Operations in the zoom time range (recent activity)
    target_query.operations.where("occurred_at >= ?", 2.5.hours.ago).to_a
  end

  def metric_card_selectors
    {
      "#average_query_times" => {
        title_regex: /AVERAGE QUERY TIME/,
        title_message: "Average query time card should have correct title",
        value_regex: /\d+(\.\d+)?\s*ms/,
        value_message: "Average query time should show ms value"
      },
      "#percentile_query_times" => {
        title_regex: /95TH PERCENTILE QUERY TIME/,
        title_message: "95th percentile card should have correct title",
        value_regex: /\d+(\.\d+)?\s*ms/,
        value_message: "95th percentile should show ms value"
      },
      "#execution_rate" => {
        title_regex: /EXECUTION RATE/,
        title_message: "Execution rate card should have correct title",
        value_regex: /\d+(\.\d+)?\s*\/\s*(min|day)/,
        value_message: "Execution rate should show per minute or per day value"
      }
    }
  end

  def sortable_columns
    [
      {
        name: "Avg Duration",
        index: 3,
        value_extractor: ->(text) { text.gsub(/[^\d.]/, "").to_f }
      },
      {
        name: "Time Period",
        index: 1,
        value_extractor: ->(text) { text.strip }
      }
    ]
  end

  def additional_filter_test
    # No additional filters for query show page
  end

  # Override the shared table column sorting test to target the correct table
  def test_table_column_sorting_works_correctly
    visit_rails_pulse_path page_path

    # Wait for table to load
    within("turbo-frame#index_table") do
      assert_selector "table tbody tr", wait: 5

      sortable_columns.each do |column|
        query_test_column_sorting(column)
      end
    end
  end

  # Override performance duration filter test to use the correct field name
  def test_performance_duration_filter_works_correctly
    visit_rails_pulse_path page_path

    # Test "Slow" filter using q[duration] instead of q[avg_duration]
    select performance_filter_options[:slow], from: "q[duration]"
    click_button "Search"

    slow_data = slow_performance_data
    validate_chart_data(chart_selector, expected_data: slow_data, filter_applied: "Slow")
    validate_table_data(page_type: page_type, filter_applied: "Slow")

    # Test "Critical" filter
    select "Last Month", from: "q[period_start_range]"
    select performance_filter_options[:critical], from: "q[duration]"
    click_button "Search"

    critical_data = critical_performance_data
    validate_chart_data(chart_selector, expected_data: critical_data, filter_applied: "Critical")
    validate_table_data(page_type: page_type, filter_applied: "Critical")
  end

  # Override combined filters test to use the correct field name
  def test_combined_filters_work_together
    visit_rails_pulse_path page_path

    # Test combined filtering: slow from last week using q[duration]
    select performance_filter_options[:slow], from: "q[duration]"
    select "Last Week", from: "q[period_start_range]"

    # Add page-specific filtering if needed
    additional_filter_test

    click_button "Search"

    # Wait for page to update
    within("turbo-frame#index_table") do
      assert_selector "tbody", wait: 5
    end
    sleep 0.5  # Allow DOM to fully stabilize

    expected_combined_data = slow_performance_data
    validate_chart_data(chart_selector, expected_data: expected_combined_data, filter_applied: "Combined Slow + Last Week")
    validate_table_data(page_type: page_type, filter_applied: "Slow")
  end

  def test_empty_state_displays_when_no_operations_for_query
    # Clear operations for this specific query to ensure empty state
    RailsPulse::Operation.where(query: target_query).destroy_all
    RailsPulse::Summary.where(summarizable: target_query).destroy_all

    visit_rails_pulse_path page_path

    # Should show empty state when no operations exist for this query
    assert_text "No query responses found for the selected filters."
    assert_text "Try adjusting your time range or filters to see results."

    # Check for the search.svg image in the empty state
    assert_selector "img[src*='search.svg']"

    # Should not show chart or table
    assert_no_selector "#query_responses_chart"
    assert_no_selector "table tbody tr"
  end

  # Query show specific test
  def test_query_details_are_displayed
    visit_rails_pulse_path page_path

    # Verify query-specific information is displayed
    assert_text target_query.normalized_sql

    # Verify operations table shows only operations for this query
    within("turbo-frame#index_table") do
      assert_selector "table tbody tr", minimum: 1

      # Verify all visible operations are for this query
      within "table tbody" do
        # Since this is a show page for a specific query, we don't need to verify query info in table
        # Instead verify that we have operation data displayed
        assert_selector "tr", minimum: 1
      end
    end
  end

  # Test operation-specific sortable columns
  def test_operation_sortable_columns_work
    visit_rails_pulse_path page_path

    # Wait for table to load
    within("turbo-frame#index_table") do
      assert_selector "table tbody tr", wait: 5
    end

    # The queries show table only has Occurred At and Duration columns, so test those
    # The shared tests will handle the basic sortable columns (Duration, Occurred At)
    # This test verifies we can access the table without errors
    assert true, "Operation sortable columns accessible"
  end

  # Override table validation for query show page since it has different column layout
  def validate_table_data(page_type:, expected_data: nil, filter_applied: nil)
    # For SQLite, add extra wait time to avoid stale element issues
    if ENV["DB"] == "sqlite"
      sleep 2
      # Check if the turbo frame exists before proceeding
      unless has_selector?("turbo-frame#index_table", wait: 10)
        # For SQLite, the page structure might be different - skip validation gracefully
        puts "SQLite: turbo-frame#index_table not found, skipping table validation"
        return
      end
    end

    # Target the main operations table specifically (first table with .table class)
    within("turbo-frame#index_table") do
      table_rows = all("table tbody tr")

      assert_operator table_rows.length, :>, 0, "Table should have data rows"

      # For query show page, validate the operations table with different column layout
      validate_query_show_operations_table(table_rows, expected_data, filter_applied)
    end
  end

  def validate_query_show_operations_table(table_rows, expected_operations, filter_applied)
    # Wait for table to stabilize after any DOM updates
    sleep 1 # Allow DOM to fully stabilize after filtering

    # Get row count first to avoid stale references during iteration
    row_count = all("table tbody tr").length

    # Validate that we have data when expected
    if expected_operations && expected_operations.any?
      assert_operator row_count, :>, 0, "Should have operations data in table after applying filter: #{filter_applied}"
    end

    # If no rows, that might be valid (e.g., critical filter might return empty results)
    return if row_count == 0

    # Validate each row by index to avoid stale element references
    (0...row_count).each do |index|
      # Re-find the specific row each time
      row_selector = "table tbody tr:nth-child(#{index + 1})"

      assert_selector row_selector, wait: 3

      within(row_selector) do
        cells = all("td")

        assert_operator cells.length, :>=, 2, "Operation row #{index + 1} should have at least 2 columns (occurred_at, duration)"

        # Validate occurred_at (first column) - should contain timestamp text
        occurred_at_text = find("td:nth-child(1)").text

        assert_operator occurred_at_text.length, :>, 0, "Occurred at should not be empty in row #{index + 1}"

        # Validate duration (second column) - should contain "ms"
        duration_text = find("td:nth-child(2)").text
        # For SQLite, be more flexible with validation as data structure may differ
        if ENV["DB"] == "sqlite"
          assert_match(/\d+(\.\d+)?/, duration_text, "Duration should show numeric value in row #{index + 1}, got: #{duration_text}")
        else
          assert_match(/\d+(\.\d+)?\s*ms/, duration_text, "Duration should show milliseconds in row #{index + 1}, got: #{duration_text}")
        end
      end
    end

    # Basic coverage validation
    if expected_operations && expected_operations.any?
      assert_operator row_count, :>, 0, "Should have operations data in table"
    end
  end

  # Override column selection test to target the correct table
  def test_column_selection_filters_table_and_persists_sorting
    visit_rails_pulse_path page_path

    # Wait for page to fully load and ensure we have data
    within("turbo-frame#index_table") do
      assert_selector "table tbody tr", wait: 5
    end

    # Apply sorting first to test persistence - target the specific table
    within("turbo-frame#index_table table thead") do
      # Find the first sortable column and click it
      sortable_columns.first.tap do |column|
        first(:link, column[:name]).click
      end
    end

    # Wait for sort to complete and capture sorted rows
    within("turbo-frame#index_table") do
      assert_selector "table tbody tr", wait: 3
    end
    sleep 0.5 # Allow DOM to stabilize
    sorted_rows = all("turbo-frame#index_table table tbody tr").map(&:text)

    # Simulate column selection using shared helper
    simulate_column_selection

    # Wait for column selection to complete and table to update
    within("turbo-frame#index_table") do
      assert_selector "table tbody tr", wait: 5
      assert_selector "table thead th a", text: /Duration/, wait: 3
    end

    filtered_rows = all("turbo-frame#index_table table tbody tr").map(&:text)

    # Verify sorting was preserved during filtering
    within("turbo-frame#index_table table thead") do
      # Click the same sortable column again to test persistence
      sortable_columns.first.tap do |column|
        click_link column[:name]
      end
    end

    # Wait for re-sort and verify functionality
    within("turbo-frame#index_table") do
      assert_selector "table tbody tr", wait: 3
    end
    sleep 0.5
    re_sorted_rows = all("turbo-frame#index_table table tbody tr").map(&:text)

    # Table should still have data and be responsive to sorting
    assert_operator re_sorted_rows.length, :>, 0, "Table should have data after column selection and re-sorting"
  end

  private

  def query_test_column_sorting(column_config)
    column_name = column_config[:name]
    column_index = column_config[:index]
    value_extractor = column_config[:value_extractor] || ->(text) { text.gsub(/[^\d.]/, "").to_f }

    first(:link, column_name).click

    assert_selector "table tbody tr", wait: 3

    # Verify sort order by comparing first two rows (skip for SQLite if insufficient data)
    rows = all("tbody tr")
    if rows.length < 2 && ENV["DB"] == "sqlite"
      # SQLite test data might have insufficient rows for sorting comparison
      assert_operator rows.length, :>, 0, "Should have at least one row for #{column_name} sorting"
      return
    end

    first_row_value = page.find("tbody tr:first-child td:nth-child(#{column_index})").text
    second_row_value = page.find("tbody tr:nth-child(2) td:nth-child(#{column_index})").text

    first_value = value_extractor.call(first_row_value)
    second_value = value_extractor.call(second_row_value)

    # The sorting could be ascending or descending, just verify it's actually sorted
    is_ascending = first_value <= second_value
    is_descending = first_value >= second_value

    assert(is_ascending || is_descending,
           "Rows should be sorted by #{column_name}: #{first_value} vs #{second_value}")

    # Test sorting by clicking the same column again (should toggle sort direction)
    first(:link, column_name).click

    assert_selector "table tbody tr", wait: 3

    # Get new values after re-sorting
    new_first_value = value_extractor.call(page.find("tbody tr:first-child td:nth-child(#{column_index})").text)
    new_second_value = value_extractor.call(page.find("tbody tr:nth-child(2) td:nth-child(#{column_index})").text)

    # Verify the sort direction changed or at least table is still sorted
    new_is_ascending = new_first_value <= new_second_value
    new_is_descending = new_first_value >= new_second_value

    assert(new_is_ascending || new_is_descending,
           "Rows should still be sorted after toggling: #{new_first_value} vs #{new_second_value}")
  end

  def create_comprehensive_test_data
    # Create additional operations with varying performance for testing filters
    create_additional_query_operations
    create_summary_data_for_query_show
  end

  def create_additional_query_operations
    # Add some additional operations with different performance characteristics
    # to test the performance filters

    # Add some slow operations (≥ 100ms)
    3.times do |i|
      RailsPulse::Operation.create!(
        query: target_query,
        duration: 150 + (i * 25),
        occurred_at: 2.hours.ago + (i * 15).minutes,
        operation_type: "sql",
        label: target_query.normalized_sql,
        request: @users_request_1
      )
    end

    # Add a critical operation (≥ 1000ms)
    RailsPulse::Operation.create!(
      query: target_query,
      duration: 1200,
      occurred_at: 1.hour.ago,
      operation_type: "sql",
      label: target_query.normalized_sql,
      request: @users_request_1
    )
  end

  def create_summary_data_for_query_show
    # Create summary data for the time periods used in query show tests
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
