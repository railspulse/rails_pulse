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
    "#average_response_times_chart"
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
    # api_users route has 600ms and 650ms requests created at 12 hours ago
    # Combined with fixture requests, avg will be >= 500ms
    [ rails_pulse_routes(:api_users) ]
  end

  def critical_performance_data
    # api_posts route has 3500ms request created at 10 days ago
    [ rails_pulse_routes(:api_posts) ]
  end

  def zoomed_data
    # api_test route has request at 2 hours ago (within 2.5-1.5 hours range)
    [ rails_pulse_routes(:api_test) ]
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
        name: "Average Response Time",
        index: 1,
        value_extractor: ->(text) { text.gsub(/[^\d.]/, "").to_f }
      },
      {
        name: "Max Response Time",
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
    # Create additional requests with specific performance characteristics
    create_performance_test_requests
    # Generate summary data for the routes index page
    create_summary_data_for_routes
  end

  def create_performance_test_requests
    # Create slow requests (≥500ms) for api_users route
    api_users_route = rails_pulse_routes(:api_users)

    # Fixtures have users_request_1 (150.5ms @ 1 hour ago) and users_request_2 (250ms @ 2 hours ago)
    # We need to ensure the daily average is >= 500ms for the "slow" filter
    # Create multiple slow requests to bring the average up
    4.times do |i|
      RailsPulse::Request.create!(
        route: api_users_route,
        duration: 700.0 + (i * 50),  # 700ms, 750ms, 800ms, 850ms
        occurred_at: 12.hours.ago + (i * 10).minutes,
        status: 200,
        is_error: false,
        request_uuid: "test-routes-slow-#{i}",
        controller_action: "Api::UsersController#index"
      )
    end

    # Create critical requests (≥3000ms) for api_posts route at 10 days ago (within Last Month)
    api_posts_route = rails_pulse_routes(:api_posts)

    RailsPulse::Request.create!(
      route: api_posts_route,
      duration: 3500.0,  # Well above 3000ms critical threshold
      occurred_at: 10.days.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-routes-critical-1",
      controller_action: "Api::PostsController#create"
    )

    # Create request for zoom range test (between 2.5 and 1.5 hours ago)
    api_test_route = rails_pulse_routes(:api_test)

    RailsPulse::Request.create!(
      route: api_test_route,
      duration: 250.0,
      occurred_at: 2.hours.ago,
      status: 200,
      is_error: false,
      request_uuid: "test-routes-zoom-1",
      controller_action: "Api::TestController#index"
    )
  end

  def create_summary_data_for_routes
    # Create hour-level summaries for precise time periods
    service = RailsPulse::SummaryService.new("hour", 12.hours.ago.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("hour", 10.days.ago.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("hour", 2.hours.ago.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("hour", 1.hour.ago.beginning_of_hour)
    service.perform

    # Create day-level summaries for longer time ranges (Last Week, Last Month)
    # These aggregate the hour-level data
    service = RailsPulse::SummaryService.new("day", Time.current.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("day", 12.hours.ago.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("day", 10.days.ago.beginning_of_day)
    service.perform
  end
end
