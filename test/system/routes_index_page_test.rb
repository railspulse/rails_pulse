require "test_helper"

class RoutesIndexPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_routes, :rails_pulse_summaries

  test "routes index page loads with all major sections" do
    assert_page_loads "/routes"
    assert_metric_cards_present(count: 3)
    assert_chart_renders "response_time_percentiles_chart"
    assert_table_has_data
  end
end
