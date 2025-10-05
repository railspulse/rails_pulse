require "test_helper"
require_relative "../support/shared_index_page_test"

class RoutesIndexPageTest < SharedIndexPageTest
  def page_path
    "/routes"
  end

  def page_type
    :routes
  end

  def chart_selector
    "#routes_chart"
  end

  def performance_filter_options
    {
      slow: "Slow (≥ 500ms)",
      critical: "Critical (≥ 3000ms)"
    }
  end

  def all_test_data
    RailsPulse::Route.all.to_a
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
    # Routes with slow average response time (calculated from their requests)
    all_test_data.select do |route|
      avg_duration = route.requests.average(:duration)
      avg_duration && avg_duration >= 500
    end
  end

  def critical_performance_data
    # Routes with critical average response time (calculated from their requests)
    all_test_data.select do |route|
      avg_duration = route.requests.average(:duration)
      avg_duration && avg_duration >= 3000
    end
  end

  def zoomed_data
    # Routes that have recent activity
    route_ids_with_recent_activity = RailsPulse::Request.where("occurred_at >= ?", 2.5.hours.ago).distinct.pluck(:route_id)
    all_test_data.select { |route| route_ids_with_recent_activity.include?(route.id) }
  end

  def metric_card_selectors
    {
      "#average_response_times" => {
        title_regex: /AVERAGE RESPONSE TIME/,
        title_message: "Average response time card should have correct title",
        value_regex: /\d+(\.\d+)?\s*ms/,
        value_message: "Average response time should show ms value"
      },
      "#percentile_response_times" => {
        title_regex: /95TH PERCENTILE RESPONSE TIME/,
        title_message: "95th percentile card should have correct title",
        value_regex: /\d+(\.\d+)?\s*ms/,
        value_message: "95th percentile should show ms value"
      },
      "#request_count_totals" => {
        title_regex: /REQUEST COUNT TOTAL/,
        title_message: "Request count card should have correct title",
        value_regex: /\d+(\.\d+)?\s*\/\s*(min|day)/,
        value_message: "Request count should show per minute or per day value"
      },
      "#error_rate_per_route" => {
        title_regex: /ERROR RATE PER ROUTE/,
        title_message: "Error rate card should have correct title",
        value_regex: /\d+(\.\d+)?%/,
        value_message: "Error rate should show percentage value"
      }
    }
  end

  def sortable_columns
    [
      {
        name: "Response Time",
        index: 1,
        value_extractor: ->(text) { text.gsub(/[^\d.]/, "").to_f }
      },
      {
        name: "Error Rate",
        index: 2,
        value_extractor: ->(text) { text.gsub(/[^\d.]/, "").to_f }
      }
    ]
  end

  def additional_filter_test
    # No additional filters for routes index page
  end

  private

  def create_comprehensive_test_data
    # Shared data provides basic routes, requests, queries, and operations
    # Just need to create summary data for the routes index page
    create_summary_data_for_routes
  end

  def create_summary_data_for_routes
    # Create summary data for the time periods used in routes index tests
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
