require "test_helper"

class DashboardIndexPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_summaries

  test "dashboard renders all major ui sections" do
    visit_rails_pulse_path "/"

    # System Health Bar
    assert_selector ".dashboard-health-bar"

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
end
