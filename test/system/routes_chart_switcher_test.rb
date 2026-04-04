require "test_helper"
require_relative "../support/shared_test_data"

class RoutesChartSwitcherTest < ApplicationSystemTestCase
  include SharedTestData

  fixtures :rails_pulse_routes, :rails_pulse_requests, :rails_pulse_summaries

  CHART_IDS = {
    response_time: "response_time_percentiles_chart",
    request_volume: "request_volume_chart",
    error_rate: "error_rate_chart"
  }.freeze

  def setup
    super
    load_shared_test_data
    create_chart_summaries
    visit_rails_pulse_path "/routes?q[period_start_range]=last_month"
    assert_selector "#response_time_percentiles_chart[data-chart-rendered='true']", wait: 10
  end

  # ── Zone 1 default state ────────────────────────────────────────────────────

  test "response time chart is visible and others are hidden by default" do
    assert_chart_container_visible(:response_time)
    assert_chart_container_hidden(:request_volume)
    assert_chart_container_hidden(:error_rate)
  end

  test "response time tab is active by default" do
    assert_tab_active(:response_time)
    assert_tab_inactive(:request_volume)
    assert_tab_inactive(:error_rate)
  end

  test "p95 p99 toggles are visible for response time by default" do
    assert_toggles_visible(:response_time)
    assert_toggles_hidden(:error_rate)
  end

  # ── Tab switching ────────────────────────────────────────────────────────────

  test "switching to request volume shows that chart and hides others" do
    click_tab(:request_volume)
    assert_selector "#request_volume_chart[data-chart-rendered='true']", wait: 10

    assert_chart_container_visible(:request_volume)
    assert_chart_container_hidden(:response_time)
    assert_chart_container_hidden(:error_rate)
  end

  test "switching to error rates shows that chart and hides others" do
    click_tab(:error_rate)
    assert_selector "#error_rate_chart[data-chart-rendered='true']", wait: 10

    assert_chart_container_visible(:error_rate)
    assert_chart_container_hidden(:response_time)
    assert_chart_container_hidden(:request_volume)
  end

  test "active tab data-active attribute updates correctly on switch" do
    click_tab(:request_volume)
    sleep 0.3

    assert_tab_active(:request_volume)
    assert_tab_inactive(:response_time)
    assert_tab_inactive(:error_rate)

    click_tab(:error_rate)
    sleep 0.3

    assert_tab_active(:error_rate)
    assert_tab_inactive(:response_time)
    assert_tab_inactive(:request_volume)
  end

  # ── Contextual series toggles ────────────────────────────────────────────────

  test "no series toggles are visible when request volume is active" do
    click_tab(:request_volume)
    sleep 0.3

    assert_toggles_hidden(:response_time)
    assert_toggles_hidden(:error_rate)
  end

  test "errors and client toggles appear when error rates is active" do
    click_tab(:error_rate)
    sleep 0.3

    assert_toggles_visible(:error_rate)
    assert_toggles_hidden(:response_time)
  end

  test "switching back to response time restores p95 p99 toggles" do
    click_tab(:error_rate)
    sleep 0.3
    assert_toggles_visible(:error_rate)
    assert_toggles_hidden(:response_time)

    click_tab(:response_time)
    sleep 0.3
    assert_toggles_visible(:response_time)
    assert_toggles_hidden(:error_rate)
  end

  # ── Table updates from all charts ────────────────────────────────────────────

  test "zooming request volume chart updates table and url" do
    click_tab(:request_volume)
    assert_selector "#request_volume_chart[data-chart-rendered='true']", wait: 10

    zoomed = apply_chart_zoom("request_volume_chart")
    skip "Not enough data points to zoom" unless zoomed

    sleep 1.5 # Allow debounce + fetch

    assert_includes page.current_url, "zoom_start_time",
      "URL should include zoom_start_time after zooming request volume chart"
    assert_includes page.current_url, "zoom_end_time",
      "URL should include zoom_end_time after zooming request volume chart"
  end

  test "zooming error rate chart updates table and url" do
    click_tab(:error_rate)
    assert_selector "#error_rate_chart[data-chart-rendered='true']", wait: 10

    zoomed = apply_chart_zoom("error_rate_chart")
    skip "Not enough data points to zoom" unless zoomed

    sleep 1.5

    assert_includes page.current_url, "zoom_start_time",
      "URL should include zoom_start_time after zooming error rate chart"
  end

  # ── Zoom persistence across chart switches ───────────────────────────────────

  test "zoom applied to response time persists when switching to request volume" do
    assert_selector "#response_time_percentiles_chart[data-chart-rendered='true']", wait: 10

    zoom_state = apply_chart_zoom_and_capture("response_time_percentiles_chart")
    skip "Not enough data points to test zoom persistence" unless zoom_state

    click_tab(:request_volume)
    assert_selector "#request_volume_chart[data-chart-rendered='true']", wait: 10
    sleep 0.5

    rv_zoom = read_chart_zoom("request_volume_chart")

    assert rv_zoom, "Request volume chart should have zoom state after switching"
    assert_equal zoom_state["start"], rv_zoom["startValue"],
      "Zoom start index should carry over to request volume chart"
    assert_equal zoom_state["end"], rv_zoom["endValue"],
      "Zoom end index should carry over to request volume chart"
  end

  test "zoom persists when switching through all three charts" do
    assert_selector "#response_time_percentiles_chart[data-chart-rendered='true']", wait: 10

    zoom_state = apply_chart_zoom_and_capture("response_time_percentiles_chart")
    skip "Not enough data points to test zoom persistence" unless zoom_state

    # Switch to Request Volume and verify zoom
    click_tab(:request_volume)
    assert_selector "#request_volume_chart[data-chart-rendered='true']", wait: 10
    sleep 0.5
    rv_zoom = read_chart_zoom("request_volume_chart")
    assert rv_zoom, "Request volume should inherit zoom"
    assert_equal zoom_state["start"], rv_zoom["startValue"]

    # Switch to Error Rates and verify zoom carries from request volume
    click_tab(:error_rate)
    assert_selector "#error_rate_chart[data-chart-rendered='true']", wait: 10
    sleep 0.5
    er_zoom = read_chart_zoom("error_rate_chart")
    assert er_zoom, "Error rate chart should inherit zoom"
    assert_equal zoom_state["start"], er_zoom["startValue"]
  end

  test "switching back to a chart after zoom preserves its listeners" do
    # Switch away and back — listeners should still work
    click_tab(:request_volume)
    assert_selector "#request_volume_chart[data-chart-rendered='true']", wait: 10

    click_tab(:response_time)
    assert_selector "#response_time_percentiles_chart[data-chart-rendered='true']", wait: 5
    sleep 0.5

    # Apply zoom on response time after switching back — URL should still update
    zoomed = apply_chart_zoom("response_time_percentiles_chart")
    skip "Not enough data points" unless zoomed

    sleep 1.5
    assert_includes page.current_url, "zoom_start_time",
      "Response time chart should still update URL after switching back"
  end

  # ── Chart data integrity ─────────────────────────────────────────────────────

  test "all three charts render with valid series data" do
    [ :request_volume, :error_rate ].each do |chart_type|
      click_tab(chart_type)
      chart_id = CHART_IDS[chart_type]
      assert_selector "##{chart_id}[data-chart-rendered='true']", wait: 10

      series_count = page.execute_script(<<~JS)
        var el = document.getElementById('#{chart_id}');
        if (!el) return 0;
        var chart = echarts.getInstanceByDom(el);
        if (!chart) return 0;
        return (chart.getOption().series || []).length;
      JS

      assert_operator series_count, :>, 0,
        "#{chart_id} should have at least one series after switching"
    end
  end

  test "response time chart handles nil data points without errors" do
    assert_selector "#response_time_percentiles_chart[data-chart-rendered='true']", wait: 10

    result = page.execute_script(<<~JS)
      var el = document.getElementById('response_time_percentiles_chart');
      if (!el) return { rendered: false };
      var chart = echarts.getInstanceByDom(el);
      if (!chart) return { rendered: false };
      var option = chart.getOption();
      var series = option.series || [];
      var allPoints = series.flatMap(function(s) { return s.data || []; });
      var nilCount = allPoints.filter(function(d) { return d === null || d === undefined; }).length;
      return { rendered: true, totalPoints: allPoints.length, nilPoints: nilCount };
    JS

    assert result["rendered"], "Chart should render successfully"
    assert_operator result["totalPoints"], :>, 0, "Chart should have data points"
    # nil points are valid — gaps in data are expected and handled
  end

  private

  # ── Assertions ───────────────────────────────────────────────────────────────

  def assert_chart_container_visible(type)
    display = chart_container_display(type)
    assert_equal "block", display,
      "#{type} chart container should be visible (display: block), got: #{display}"
  end

  def assert_chart_container_hidden(type)
    display = chart_container_display(type)
    assert_equal "none", display,
      "#{type} chart container should be hidden (display: none), got: #{display}"
  end

  def assert_tab_active(type)
    active = tab_data_active(type)
    assert_equal "true", active,
      "#{type} tab should have data-active=true, got: #{active}"
  end

  def assert_tab_inactive(type)
    active = tab_data_active(type)
    assert_equal "false", active,
      "#{type} tab should have data-active=false, got: #{active}"
  end

  def assert_toggles_visible(type)
    display = toggle_group_display(type)
    assert_not_equal "none", display,
      "#{type} toggle group should be visible, got display: #{display}"
  end

  def assert_toggles_hidden(type)
    display = toggle_group_display(type)
    assert_equal "none", display,
      "#{type} toggle group should be hidden (display: none), got: #{display}"
  end

  # ── JS helpers ───────────────────────────────────────────────────────────────

  def click_tab(type)
    find(".panel-tab[data-chart-type='#{type}']").click
  end

  def chart_container_display(type)
    page.execute_script(<<~JS)
      var el = document.querySelector('[data-chart-type="#{type}"][data-rails-pulse--chart-switcher-target="chart"]');
      return el ? el.style.display : 'not found';
    JS
  end

  def tab_data_active(type)
    page.execute_script(<<~JS)
      var el = document.querySelector('.panel-tab[data-chart-type="#{type}"]');
      return el ? el.dataset.active : 'not found';
    JS
  end

  def toggle_group_display(type)
    page.execute_script(<<~JS)
      var el = document.querySelector('.panel-tabs__toggles[data-chart-type="#{type}"]');
      return el ? el.style.display : 'none';
    JS
  end

  # Applies a zoom to the middle third of a chart's data.
  # Returns true if zoom was applied, false if not enough data.
  def apply_chart_zoom(chart_id)
    page.execute_script(<<~JS)
      var el = document.getElementById('#{chart_id}');
      if (!el) return false;
      var chart = echarts.getInstanceByDom(el);
      if (!chart) return false;
      var option = chart.getOption();
      var dataLen = (option.xAxis[0] && option.xAxis[0].data) ? option.xAxis[0].data.length : 0;
      if (dataLen < 4) return false;
      var start = Math.floor(dataLen / 3);
      var end = Math.floor(2 * dataLen / 3);
      chart.dispatchAction({ type: 'dataZoom', startValue: start, endValue: end });
      return true;
    JS
  end

  # Applies zoom and returns the start/end indices used, or nil if insufficient data.
  def apply_chart_zoom_and_capture(chart_id)
    result = page.execute_script(<<~JS)
      var el = document.getElementById('#{chart_id}');
      if (!el) return null;
      var chart = echarts.getInstanceByDom(el);
      if (!chart) return null;
      var option = chart.getOption();
      var dataLen = (option.xAxis[0] && option.xAxis[0].data) ? option.xAxis[0].data.length : 0;
      if (dataLen < 4) return null;
      var start = Math.floor(dataLen / 4);
      var end = Math.floor(3 * dataLen / 4);
      chart.dispatchAction({ type: 'dataZoom', startValue: start, endValue: end });
      return { start: start, end: end };
    JS
    result
  end

  # Reads the current dataZoom startValue/endValue from a chart instance.
  def read_chart_zoom(chart_id)
    page.execute_script(<<~JS)
      var el = document.getElementById('#{chart_id}');
      if (!el) return null;
      var chart = echarts.getInstanceByDom(el);
      if (!chart) return null;
      var option = chart.getOption();
      var dz = option.dataZoom && (option.dataZoom[1] || option.dataZoom[0]);
      return dz ? { startValue: dz.startValue, endValue: dz.endValue } : null;
    JS
  end

  # ── Test data ────────────────────────────────────────────────────────────────

  def create_chart_summaries
    # Create day-level summaries across the last 2 weeks so all 3 charts have data to display
    route = rails_pulse_routes(:api_users)

    14.downto(1) do |days_ago|
      period_start = days_ago.days.ago.beginning_of_day
      next if RailsPulse::Summary.exists?(
        summarizable: route,
        period_type: "day",
        period_start: period_start
      )

      RailsPulse::Summary.create!(
        summarizable: route,
        period_type: "day",
        period_start: period_start,
        period_end: period_start.end_of_day,
        count: 50 + (days_ago * 3),
        avg_duration: 150.0 + (days_ago * 5),
        min_duration: 80.0,
        max_duration: 400.0,
        p95_duration: 280.0 + (days_ago * 8),
        p99_duration: 380.0 + (days_ago * 10),
        error_count: days_ago == 7 ? 5 : 0,
        status_4xx: days_ago == 5 ? 3 : 0,
        success_count: 50 + (days_ago * 3)
      )
    end
  end
end
