require "test_helper"

class DashboardIndexPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_summaries

  test "dashboard renders all major ui sections" do
    visit_rails_pulse_path "/"

    # System Health Bar
    assert_text "SYSTEM HEALTH"
    assert_selector ".dashboard-health-bar"
    assert_selector ".dashboard-health-bar__period-button", count: 3

    # Health badges
    assert_text "Routes"
    assert_text "Queries"

    # Metric Strip - verify 3 metric titles present
    assert_selector ".metric-strip"
    assert_text "P95 RESPONSE TIME"
    assert_text "REQUEST RATE"
    assert_text "ERROR RATE"

    # Charts
    assert_selector "#response_time_percentiles_chart"
    assert_selector "#throughput_and_errors_chart"

    # Needs Attention Panel
    assert_text "NEEDS ATTENTION"
  end

  test "period selector updates dashboard via turbo frame" do
    visit_rails_pulse_path "/"

    # Initial state - 7 days active by default
    assert_selector ".dashboard-health-bar__period-button[data-active='true']", text: "7d"

    # Click 14 days button
    click_link "14d"

    # Verify URL updated
    assert_current_path "/rails_pulse/?period=14"

    # Verify 14 days button now active
    assert_selector ".dashboard-health-bar__period-button[data-active='true']", text: "14d"

    # Verify content updated (metric strip still present)
    assert_selector ".metric-strip"

    # Verify charts re-rendered with new data
    assert_selector "#response_time_percentiles_chart canvas"
    assert_selector "#throughput_and_errors_chart canvas"

    # Verify metric cards show actual values (not loading state)
    assert_selector ".metric-strip__section", minimum: 3
    assert_text "ms" # P95 response time value
    assert_text "Compared to last week" # Trend text present
  end
end
