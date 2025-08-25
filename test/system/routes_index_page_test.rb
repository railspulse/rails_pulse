require "support/application_system_test_case"

class RoutesIndexPageTest < ApplicationSystemTestCase
  include BulkDataHelpers

  def setup
    # Set up configuration before any queries are executed
    stub_rails_pulse_configuration({
      route_thresholds: { slow: 500, very_slow: 1500, critical: 3000 },
      request_thresholds: { fast: 100, slow: 500, critical: 1000 },
      query_thresholds: { fast: 50, slow: 200, critical: 500 }
    })
    super
    create_comprehensive_test_data
  end

  test "routes index page loads and displays data" do
    visit_rails_pulse_path "/routes"
  end

  private

  def create_comprehensive_test_data
    # Generate comprehensive test data for pagination and week-over-week testing
    # This creates:
    # - 25 diverse routes with realistic API paths
    # - 120 requests spread over 2 weeks (60 per week)
    # - 30 diverse SQL queries
    # - 1-3 operations per request
    # - Realistic performance distribution (fast/slow/errors)
    @test_data = generate_pagination_test_data

    # Create Summary data needed for routes index page
    create_summary_data_for_routes
  end

  def create_summary_data_for_routes
    # Run summarization for different time periods to ensure data shows up
    periods = [
      ["hour", 1.hour.ago],
      ["day", 1.day.ago],
      ["week", 1.week.ago]
    ]

    periods.each do |period_type, start_time|
      service = RailsPulse::SummaryService.new(period_type, start_time)
      service.perform
    end
  end
end
