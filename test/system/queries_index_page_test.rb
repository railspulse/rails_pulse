require "test_helper"

class QueriesIndexPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_queries, :rails_pulse_summaries

  test "queries index page loads with all major sections" do
    assert_page_loads "/queries"
    assert_metric_cards_present(count: 3)
    assert_chart_renders "query_performance_chart"
    assert_table_has_data
  end
end
