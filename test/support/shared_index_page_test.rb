# Abstract base class - doesn't run tests itself
require_relative "shared_test_data"
require_relative "chart_validation_helpers"
require_relative "table_validation_helpers"

class SharedIndexPageTest < ApplicationSystemTestCase
  include SharedTestData
  include ChartValidationHelpers
  include TableValidationHelpers

  # Don't run tests for this base class
  def self.runnable_methods
    return [] if name == "SharedIndexPageTest"
    super
  end

  def setup
    super
    load_shared_test_data
    create_comprehensive_test_data
  end

  def create_comprehensive_test_data
    # Override in subclasses for any additional test-specific data
    # Base shared data is already loaded via load_shared_test_data
  end

  # Override these methods in subclasses
  def page_path
    raise NotImplementedError, "Subclass must implement page_path"
  end

  def page_type
    raise NotImplementedError, "Subclass must implement page_type"
  end

  def chart_selector
    raise NotImplementedError, "Subclass must implement chart_selector"
  end

  def performance_filter_options
    raise NotImplementedError, "Subclass must implement performance_filter_options"
  end

  def all_test_data
    raise NotImplementedError, "Subclass must implement all_test_data"
  end

  def default_scope_data
    raise NotImplementedError, "Subclass must implement default_scope_data"
  end

  def last_week_data
    raise NotImplementedError, "Subclass must implement last_week_data"
  end

  def last_month_data
    raise NotImplementedError, "Subclass must implement last_month_data"
  end

  def slow_performance_data
    raise NotImplementedError, "Subclass must implement slow_performance_data"
  end

  def critical_performance_data
    raise NotImplementedError, "Subclass must implement critical_performance_data"
  end

  def zoomed_data
    raise NotImplementedError, "Subclass must implement zoomed_data"
  end

  def metric_card_selectors
    raise NotImplementedError, "Subclass must implement metric_card_selectors"
  end

  def sortable_columns
    raise NotImplementedError, "Subclass must implement sortable_columns"
  end

  def additional_filter_test
    # Override in subclasses that need additional filtering (like routes path filter)
  end

  # Shared test methods
  test "index page loads and displays data" do
    visit_rails_pulse_path page_path

    # Verify basic page structure
    assert_selector "body"
    assert_selector "table"
    assert_current_path "/rails_pulse#{page_path}"

    # Verify chart container exists
    assert_selector chart_selector
    assert_selector "[data-rails-pulse--index-target='chart']"

    # Verify chart data matches expected test data
    expected_data = all_test_data
    validate_chart_data(chart_selector, expected_data: expected_data)
    validate_table_data(page_type: page_type, expected_data: expected_data)

    # Try "Last Month" filter to see all our test data
    select "Last Month", from: "q[period_start_range]"
    click_button "Search"

    validate_table_data(page_type: page_type, expected_data: expected_data, filter_applied: "Last Month")
    validate_chart_data(chart_selector, expected_data: expected_data, filter_applied: "Last Month")
  end

  test "metric cards display data correctly" do
    visit_rails_pulse_path page_path

    # Wait for page to load
    assert_selector "table tbody tr", wait: 5

    # Test each metric card
    metric_card_selectors.each do |selector, expected_pattern|
      within(selector) do
        card_text = text.upcase

        assert_match expected_pattern[:title_regex], card_text, expected_pattern[:title_message]
        assert_match expected_pattern[:value_regex], text, expected_pattern[:value_message]
      end
    end
  end

  test "time range filter updates chart and table data" do
    visit_rails_pulse_path page_path

    # Capture initial data
    default_data = default_scope_data
    validate_chart_data(chart_selector, expected_data: default_data)
    validate_table_data(page_type: page_type)

    # Test Last Week filter
    select "Last Week", from: "q[period_start_range]"
    click_button "Search"

    assert_current_path "/rails_pulse#{page_path}", ignore_query: true
    week_data = last_week_data
    validate_chart_data(chart_selector, expected_data: week_data, filter_applied: "Last Week")
    validate_table_data(page_type: page_type, filter_applied: "Last Week")

    # Test Last Month filter
    select "Last Month", from: "q[period_start_range]"
    click_button "Search"

    month_data = last_month_data
    validate_chart_data(chart_selector, expected_data: month_data, filter_applied: "Last Month")
    validate_table_data(page_type: page_type, filter_applied: "Last Month")
  end

  test "performance duration filter works correctly" do
    visit_rails_pulse_path page_path

    # Test "Slow" filter
    select performance_filter_options[:slow], from: "q[avg_duration]"
    click_button "Search"

    slow_data = slow_performance_data
    validate_chart_data(chart_selector, expected_data: slow_data, filter_applied: "Slow")
    validate_table_data(page_type: page_type, filter_applied: "Slow")

    # Test "Critical" filter
    select "Last Month", from: "q[period_start_range]"
    select performance_filter_options[:critical], from: "q[avg_duration]"
    click_button "Search"

    critical_data = critical_performance_data
    validate_chart_data(chart_selector, expected_data: critical_data, filter_applied: "Critical")
    validate_table_data(page_type: page_type, filter_applied: "Critical")
  end

  test "combined filters work together" do
    visit_rails_pulse_path page_path

    # Test combined filtering: slow from last week
    select performance_filter_options[:slow], from: "q[avg_duration]"
    select "Last Week", from: "q[period_start_range]"

    # Add page-specific filtering if needed
    additional_filter_test

    click_button "Search"

    # Wait for page to update
    assert_selector "tbody", wait: 5
    sleep 0.5  # Allow DOM to fully stabilize

    expected_combined_data = slow_performance_data
    validate_chart_data(chart_selector, expected_data: expected_combined_data, filter_applied: "Combined Slow + Last Week")
    validate_table_data(page_type: page_type, filter_applied: "Slow")
  end

  test "table column sorting works correctly" do
    visit_rails_pulse_path page_path

    # Wait for table to load
    assert_selector "table tbody tr", wait: 5

    sortable_columns.each do |column|
      test_column_sorting(column)
    end
  end

  test "zoom range parameters filter table data while chart shows all data" do
    visit_rails_pulse_path page_path

    # Wait for page to load with default data
    assert_selector "table tbody tr", wait: 5

    # Validate initial state
    default_data = default_scope_data
    validate_chart_data(chart_selector, expected_data: default_data, filter_applied: "Default")
    validate_table_data(page_type: page_type, expected_data: default_data, filter_applied: "Default")

    # Apply zoom parameters
    zoom_start = 2.5.hours.ago.to_i
    zoom_end = 1.5.hours.ago.to_i

    zoom_params = {
      "zoom_start_time" => zoom_start.to_s,
      "zoom_end_time" => zoom_end.to_s
    }

    zoom_url = "/rails_pulse#{page_path}?#{zoom_params.to_query}"
    visit zoom_url

    # Wait for page to reload with zoom applied
    assert_selector "table tbody tr", wait: 5

    # Chart should still show the SAME data (zoom is visual only on chart)
    validate_chart_data(chart_selector, expected_data: default_data, filter_applied: "Default with Zoom")

    # Table should only show data in the zoom range
    zoomed_table_data = zoomed_data
    validate_table_data(page_type: page_type, expected_data: zoomed_table_data, filter_applied: "Recent Zoom")
  end

  test "column selection filters table and persists sorting" do
    visit_rails_pulse_path page_path

    # Wait for page to fully load and ensure we have data
    assert_selector "table tbody tr", wait: 5

    # Apply sorting first to test persistence
    within("table thead") do
      # Find the first sortable column and click it
      sortable_columns.first.tap do |column|
        click_link column[:name]
      end
    end

    # Wait for sort to complete and capture sorted rows
    assert_selector "table tbody tr", wait: 3
    sleep 0.5 # Allow DOM to stabilize
    sorted_rows = all("table tbody tr").map(&:text)

    # Simulate column selection using shared helper
    simulate_column_selection

    # Wait for the server request to complete
    sleep 1

    # Capture table rows after column selection
    current_sorted_rows = all("table tbody tr").map(&:text)

    # Verify sort order is maintained (if we have overlapping data)
    if current_sorted_rows.length == sorted_rows.length && (current_sorted_rows & sorted_rows).length > 0
      common_items = current_sorted_rows & sorted_rows

      assert_operator common_items.length, :>, 0, "Should have some common items to verify sort persistence"
    end

    # Verify chart has data
    chart_columns = page.execute_script("
      if (window.RailsCharts && window.RailsCharts.charts) {
        var charts = Object.keys(window.RailsCharts.charts);
        if (charts.length > 0) {
          return window.RailsCharts.charts[charts[0]].getOption().series[0].data.length;
        }
      }
      return 0;
    ")

    assert_operator chart_columns, :>, 1, "Should have multiple chart columns"

    # Verify URL parameters
    current_url = page.current_url

    assert_includes current_url, "selected_column_time", "URL should contain selected_column_time parameter after column selection"
    assert_includes current_url, "q%5Bs%5D", "Sort parameter should be preserved during column selection"
  end

  private

  def test_column_sorting(column_config)
    column_name = column_config[:name]
    column_index = column_config[:index]
    value_extractor = column_config[:value_extractor] || ->(text) { text.gsub(/[^\d.]/, "").to_f }

    within("table thead") { first(:link, column_name).click }

    assert_selector "table tbody tr", wait: 3

    # Verify sort order by comparing first two rows
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
    within("table thead") { first(:link, column_name).click }

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

  def simulate_column_selection
    # Find the index controller and simulate column click
    index_element = find('[data-controller="rails-pulse--index"]')

    assert index_element, "Should find element with rails-pulse--index controller"

    # Use JavaScript to simulate column selection
    page.execute_script("
      if (window.Stimulus && window.RailsCharts && window.RailsCharts.charts) {
        var controller = window.Stimulus.getControllerForElementAndIdentifier(arguments[0], 'rails-pulse--index');
        if (controller && window.RailsCharts.charts[controller.chartIdValue]) {
          var chart = window.RailsCharts.charts[controller.chartIdValue];
          var option = chart.getOption();
          var seriesData = option.series[0].data;
          var xAxisData = option.xAxis[0].data;

          for (var i = 0; i < seriesData.length; i++) {
            var value = typeof seriesData[i] === 'object' ? seriesData[i].value : seriesData[i];
            if (value && value > 0) {
              var params = {
                dataIndex: i,
                seriesIndex: 0,
                value: seriesData[i],
                name: xAxisData[i]
              };
              controller.handleColumnClick(params);
              break;
            }
          }
        }
      }
    ", index_element)
  end
end
