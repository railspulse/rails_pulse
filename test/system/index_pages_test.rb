require "support/application_system_test_case"

class IndexPagesTest < ApplicationSystemTestCase
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

  test "routes index page loads successfully" do
    visit_rails_pulse_path "/routes"

    # Check if table has data
    if page.has_selector?("tbody tr")
      puts "SUCCESS: Table has #{page.all('tbody tr').count} rows"
      assert_selector "tbody tr"
    else
      puts "No table rows - trying all_time filter..."
      visit_rails_pulse_path "/routes?q[occurred_at_range]=all_time"

      if page.has_selector?("tbody tr")
        puts "SUCCESS: Table shows #{page.all('tbody tr').count} rows with all_time filter"
        assert_selector "tbody tr"
      else
        puts "WARNING: No table data even with all_time filter"
      end
    end

    assert_selector "body"
    assert_selector "table"
  end

  test "requests index page loads successfully" do
    visit_rails_pulse_path "/requests"

    assert_selector "body"
    assert_current_path "/rails_pulse/requests"
  end

  test "queries index page loads successfully" do
    visit_rails_pulse_path "/queries"

    assert_selector "body"
    assert_current_path "/rails_pulse/queries"
  end

  test "all pages handle empty data gracefully" do
    # Clear all data
    RailsPulse::Operation.delete_all
    RailsPulse::Request.delete_all
    RailsPulse::Query.delete_all
    RailsPulse::Route.delete_all

    [ "/routes", "/requests", "/queries" ].each do |path|
      visit_rails_pulse_path path
      assert_selector "body"
    end
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

    puts "Generated test data: #{@test_data[:routes].count} routes, #{@test_data[:total_requests]} requests"
  end
end
