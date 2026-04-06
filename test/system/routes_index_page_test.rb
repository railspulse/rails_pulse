require "test_helper"

class RoutesIndexPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_routes, :rails_pulse_summaries

  def setup
    visit_rails_pulse_path "/routes"
    # Wait for chart to render before running tests
    page.has_selector?("#response_time_percentiles_chart[data-chart-rendered='true']", wait: 10)
  end

  # ── Smoke Tests ──────────────────────────────────────────────────────────────

  test "page loads and displays main components" do
    # Verify all major sections render
    assert_selector ".metric-strip"
    assert_selector ".metric-strip__section", count: 3
    assert_selector ".panel-tabs"
    assert_selector "#response_time_percentiles_chart"
    assert_selector "turbo-frame#index_table"
    assert_selector ".table"
  end

  test "time range selector updates page" do
    # Stimulus: index_controller updates on time range change
    select "Last Week", from: "q_period_start_range"

    assert_selector "#response_time_percentiles_chart[data-chart-rendered='true']", wait: 10
    assert_selector ".table tbody tr", minimum: 1
  end

  test "performance filter works" do
    # Stimulus: filtering updates table via dropdown
    select "Slow (≥ 500ms)", from: "q_avg_duration"
    click_button "Search"
    sleep 0.5

    assert_includes current_url, "q%5Bavg_duration%5D=slow"
  end

  test "table column sorting works" do
    # Stimulus: indexTable target + Turbo Frame
    click_link "P95"

    assert_selector "turbo-frame#index_table", wait: 5
    assert_selector ".table tbody tr", minimum: 1
  end

  test "chart zoom updates table" do
    # Stimulus: index_controller.handleZoomChange()
    apply_zoom
    sleep 1.5  # Wait for debounced zoom change (1000ms)

    assert_includes current_url, "zoom_start_time"
    assert_includes current_url, "zoom_end_time"
  end

  test "pagination limit selector works" do
    # Stimulus: index_controller.updatePaginationLimit()
    select "20", from: "limit"
    sleep 0.5

    assert_includes current_url, "limit=20"
  end

  private

  def apply_zoom
    page.execute_script(<<~JS)
      var el = document.querySelector('#response_time_percentiles_chart');
      var chart = echarts.getInstanceByDom(el);
      var dataLen = chart.getOption().xAxis[0].data.length;
      var start = Math.floor(dataLen * 0.25);
      var end = Math.floor(dataLen * 0.75);
      chart.dispatchAction({ type: 'dataZoom', startValue: start, endValue: end });
    JS
  end
end
