require "test_helper"

class QueriesIndexPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_queries, :rails_pulse_summaries

  def setup
    visit_rails_pulse_path "/queries"
    # Wait for chart to render before running tests
    page.has_selector?("#query_performance_chart[data-chart-rendered='true']", wait: 10)
  end

  # ── Smoke Tests ──────────────────────────────────────────────────────────────

  test "page loads and displays main components" do
    assert_selector ".metric-strip"
    assert_selector ".metric-strip__section", count: 3
    assert_selector ".panel-tabs"
    assert_selector "#query_performance_chart"
    assert_selector "turbo-frame#index_table"
    assert_selector ".table"
  end

  test "performance filter works" do
    select "Slow (≥ 100ms)", from: "q_avg_duration"
    click_button "Search"
    sleep 0.5

    assert_includes current_url, "q%5Bavg_duration%5D=slow"
  end

  test "table column sorting works" do
    click_link "P95"

    assert_selector "turbo-frame#index_table", wait: 5
    assert_selector ".table tbody tr", minimum: 1
  end

  test "additional sortable columns work" do
    click_link "Executions"

    assert_selector "turbo-frame#index_table", wait: 5
    assert_selector ".table tbody tr", minimum: 1

    click_link "P99"

    assert_selector "turbo-frame#index_table", wait: 5
  end

  test "chart zoom updates table" do
    apply_zoom
    sleep 1.5  # Wait for debounced zoom change (1000ms)

    assert_includes current_url, "zoom_start_time"
    assert_includes current_url, "zoom_end_time"
  end

  test "pagination limit selector works" do
    select "20", from: "limit"
    sleep 0.5

    assert_includes current_url, "limit=20"
  end

  test "empty state displays when no data matches filters" do
    # Use critical filter (≥ 1000ms) — no fixtures have durations that high
    select "Critical (≥ 1000ms)", from: "q_avg_duration"
    click_button "Search"

    assert_text "No query data found for the selected filters."
    assert_text "Try adjusting your time range or filters to see results."
    assert_selector "img[src*='search.svg']"
    assert_no_selector "#query_performance_chart"
    assert_no_selector "table tbody tr"
  end

  private

  def apply_zoom
    page.execute_script(<<~JS)
      var el = document.querySelector('#query_performance_chart');
      var chart = echarts.getInstanceByDom(el);
      var dataLen = chart.getOption().xAxis[0].data.length;
      var start = Math.floor(dataLen * 0.25);
      var end = Math.floor(dataLen * 0.75);
      chart.dispatchAction({ type: 'dataZoom', startValue: start, endValue: end });
    JS
  end
end
