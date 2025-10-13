require "test_helper"
require_relative "../support/shared_index_page_test"

class QueriesIndexPageTest < SharedIndexPageTest
  def setup
    super
  end

  # Test additional sortable columns specific to queries
  test "additional sortable columns work" do
    visit_rails_pulse_path "/queries"

    # Wait for table to load
    assert_selector "table tbody tr", wait: 5

    # Test Executions column sorting
    within("table thead") do
      click_link "Executions"
    end

    assert_selector "table tbody tr", wait: 3

    # Test Average Query Time column sorting
    within("table thead") do
      click_link "Average Query Time"
    end

    assert_selector "table tbody tr", wait: 3
  end

  test "empty state displays when no data matches filters" do
    # Clear all data to ensure empty state
    RailsPulse::Summary.destroy_all
    RailsPulse::Operation.destroy_all
    RailsPulse::Query.destroy_all

    visit_rails_pulse_path "/queries"

    # Should show empty state when no data exists
    assert_text "No query data found for the selected filters."
    assert_text "Try adjusting your time range or filters to see results."

    # Check for the search.svg image in the empty state
    assert_selector "img[src*='search.svg']"

    # Should not show chart or table
    assert_no_selector "#average_query_times_chart"
    assert_no_selector "table tbody tr"
  end

  private

  def create_summary_data_for_queries
    test_request = rails_pulse_requests(:users_request_1)

    # Create slow operations (≥100ms) for simple_query at 12 hours ago
    # Fixtures have sql_operation_3 (120ms @ 1 hour ago)
    # Add more operations to ensure average stays >= 100ms
    slow_query = rails_pulse_queries(:simple_query)
    operation_time = 12.hours.ago

    2.times do |i|
      RailsPulse::Operation.create!(
        query: slow_query,
        request: test_request,
        operation_type: "sql",
        label: slow_query.normalized_sql,
        duration: 500.0 + (i * 50),  # 500ms, 550ms
        start_time: 10.0,
        occurred_at: operation_time + (i * 10).minutes
      )
    end

    # Create critical operation (≥1000ms) for complex_query at 10 days ago (within Last Month)
    critical_query = rails_pulse_queries(:complex_query)
    critical_operation_time = 10.days.ago

    RailsPulse::Operation.create!(
      query: critical_query,
      request: test_request,
      operation_type: "sql",
      label: critical_query.normalized_sql,
      duration: 1500.0,  # Well above 1000ms critical threshold
      start_time: 10.0,
      occurred_at: critical_operation_time
    )

    # Create operation for zoom range test (between 2.5 and 1.5 hours ago)
    # Use stale_analyzed_query which currently has no operations
    zoom_query = rails_pulse_queries(:stale_analyzed_query)
    zoom_operation_time = 2.hours.ago

    RailsPulse::Operation.create!(
      query: zoom_query,
      request: test_request,
      operation_type: "sql",
      label: zoom_query.normalized_sql,
      duration: 200.0,
      start_time: 10.0,
      occurred_at: zoom_operation_time
    )

    # Generate summaries for all time periods
    service = RailsPulse::SummaryService.new("hour", operation_time.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("hour", critical_operation_time.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("hour", zoom_operation_time.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("hour", 1.hour.ago.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("day", Time.current.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("day", operation_time.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("day", critical_operation_time.beginning_of_day)
    service.perform
  end

  def create_comprehensive_test_data
    create_summary_data_for_queries
  end

  def page_path
    "/queries"
  end

  def page_type
    :queries
  end

  def chart_selector
    "#average_query_times_chart"
  end

  def performance_filter_options
    {
      slow: "Slow (≥ 100ms)",
      critical: "Critical (≥ 1000ms)"
    }
  end

  def all_test_data
    # Use fixture queries
    [ rails_pulse_queries(:simple_query), rails_pulse_queries(:complex_query), rails_pulse_queries(:analyzed_query) ]
  end

  def default_scope_data
    all_test_data
  end

  def last_week_data
    all_test_data
  end

  def last_month_data
    all_test_data
  end

  def slow_performance_data
    # Queries with avg_duration ≥ 100ms after summarization
    # simple_query gets 310ms avg (from 500ms + 500ms + 120ms operations)
    # analyzed_query gets 502ms avg (from fixture operation)
    [ rails_pulse_queries(:simple_query), rails_pulse_queries(:analyzed_query) ]
  end

  def critical_performance_data
    # Queries with avg_duration ≥ 1000ms after summarization
    # complex_query has 1500ms operation created in setup
    [ rails_pulse_queries(:complex_query) ]
  end

  def zoomed_data
    # Data within zoom range (2.5 to 1.5 hours ago)
    # stale_analyzed_query has operation at 2 hours ago
    [ rails_pulse_queries(:stale_analyzed_query) ]
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
        value_regex: /\d+(\.\d+)?\s*\/\s*(min|day|hour)/,
        value_message: "Execution rate should show per minute, per day, or per hour value"
      }
    }
  end

  def sortable_columns
    [
      {
        name: "Average Query Time",
        index: 2,
        value_extractor: ->(text) { text.gsub(/[^\d.]/, "").to_f }
      },
      {
        name: "Query",
        index: 1,
        value_extractor: ->(text) { text.strip }
      }
    ]
  end

  def additional_filter_test
    # No additional filters for queries index page
  end
end
