require "test_helper"
require_relative "../support/shared_index_page_test"

class QueriesIndexPageTest < SharedIndexPageTest
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
    RailsPulse::Query.all.to_a
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
    # Queries with slow average operation duration (≥ 100ms)
    all_test_data.select do |query|
      avg_duration = query.operations.average(:duration)
      avg_duration && avg_duration >= 100
    end
  end

  def critical_performance_data
    # Queries with critical average operation duration (≥ 1000ms)
    all_test_data.select do |query|
      avg_duration = query.operations.average(:duration)
      avg_duration && avg_duration >= 1000
    end
  end

  def zoomed_data
    # Queries that have recent activity
    query_ids_with_recent_activity = RailsPulse::Operation.where("occurred_at >= ?", 2.5.hours.ago).distinct.pluck(:query_id)
    all_test_data.select { |query| query_ids_with_recent_activity.include?(query.id) }
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

  # Test additional sortable columns specific to queries
  def test_additional_sortable_columns_work
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

  def test_empty_state_displays_when_no_data_matches_filters
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

  def create_comprehensive_test_data
    # Create additional operations with varying performance for testing filters
    create_additional_query_operations
    create_summary_data_for_queries
  end

  def create_additional_query_operations
    # Add some additional operations with different performance characteristics
    # to test the performance filters

    # Add some slow operations (≥ 100ms) for different queries
    @simple_query.tap do |query|
      2.times do |i|
        RailsPulse::Operation.create!(
          query: query,
          duration: 150 + (i * 25),
          occurred_at: 2.hours.ago + (i * 15).minutes,
          operation_type: "sql",
          label: query.normalized_sql,
          request: @users_request_1
        )
      end
    end

    # Add a critical operation (≥ 1000ms)
    @complex_query.tap do |query|
      RailsPulse::Operation.create!(
        query: query,
        duration: 1200,
        occurred_at: 1.hour.ago,
        operation_type: "sql",
        label: query.normalized_sql,
        request: @users_request_1
      )
    end
  end

  def create_summary_data_for_queries
    # Create summary data for the time periods used in queries index tests
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
