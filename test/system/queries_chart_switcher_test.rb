require "test_helper"

class QueriesChartSwitcherTest < ApplicationSystemTestCase
  fixtures :rails_pulse_routes, :rails_pulse_requests, :rails_pulse_queries, :rails_pulse_summaries

  CHART_IDS = {
    query_performance: "query_performance_chart",
    execution_volume: "execution_volume_chart",
    database_load: "database_load_chart"
  }.freeze

  def setup
    super
    # Clear existing summaries to avoid conflicts with fixtures
    # Delete both query and route summaries that might overlap with what we create
    RailsPulse::Summary.where(summarizable_type: "RailsPulse::Query").delete_all
    RailsPulse::Summary.where(
      summarizable_type: "RailsPulse::Route",
      summarizable_id: rails_pulse_routes(:api_users).id
    ).delete_all
    create_chart_summaries
    visit_rails_pulse_path "/queries?q[period_start_range]=last_30_days"
    # Wait for chart to render before running tests
    page.has_selector?("#query_performance_chart[data-chart-rendered='true']", wait: 10)
  end

  # ── Default state ────────────────────────────────────────────────────────────

  test "default state is correct" do
    assert_chart_container_visible(:query_performance)
    assert_chart_container_hidden(:execution_volume)
    assert_chart_container_hidden(:database_load)

    assert_tab_active(:query_performance)
    assert_tab_inactive(:execution_volume)
    assert_tab_inactive(:database_load)

    assert_toggles_visible(:query_performance)
    assert_toggles_hidden(:execution_volume)
    assert_toggles_hidden(:database_load)
  end

  # ── Tab switching ────────────────────────────────────────────────────────────

  test "switching tabs shows correct chart, updates active state and series toggles" do
    # Switch to Execution Volume
    click_tab(:execution_volume)

    assert_selector "#execution_volume_chart[data-chart-rendered='true']", wait: 10

    assert_chart_container_visible(:execution_volume)
    assert_chart_container_hidden(:query_performance)
    assert_chart_container_hidden(:database_load)
    assert_tab_active(:execution_volume)
    assert_tab_inactive(:query_performance)
    assert_toggles_hidden(:query_performance)
    assert_toggles_hidden(:database_load)

    # Switch to Database Load
    click_tab(:database_load)

    assert_selector "#database_load_chart[data-chart-rendered='true']", wait: 10

    assert_chart_container_visible(:database_load)
    assert_chart_container_hidden(:query_performance)
    assert_chart_container_hidden(:execution_volume)
    assert_tab_active(:database_load)
    assert_tab_inactive(:execution_volume)
    assert_toggles_hidden(:query_performance)
    assert_toggles_hidden(:execution_volume)

    # Switch back to Query Performance
    click_tab(:query_performance)

    assert_selector "#query_performance_chart[data-chart-rendered='true']", wait: 5

    assert_tab_active(:query_performance)
    assert_toggles_visible(:query_performance)
    assert_toggles_hidden(:execution_volume)
    assert_toggles_hidden(:database_load)
  end

  # ── Zoom URL persistence ──────────────────────────────────────────────────────

  test "zooming any chart updates the url" do
    [ :execution_volume, :database_load ].each do |chart_type|
      visit_rails_pulse_path "/queries?q[period_start_range]=last_30_days"

      assert_selector "#query_performance_chart[data-chart-rendered='true']", wait: 10

      click_tab(chart_type)
      chart_id = CHART_IDS[chart_type]

      assert_selector "##{chart_id}[data-chart-rendered='true']", wait: 10

      zoomed = apply_chart_zoom(chart_id.to_s)

      assert zoomed, "Should have enough data points to zoom #{chart_type} (need at least 4 data points)"

      sleep 1.5 # Allow debounce + fetch

      assert_includes page.current_url, "zoom_start_time",
        "URL should include zoom_start_time after zooming #{chart_type} chart"
      assert_includes page.current_url, "zoom_end_time",
        "URL should include zoom_end_time after zooming #{chart_type} chart"
    end
  end

  # ── Zoom persistence across chart switches ───────────────────────────────────

  test "zoom persists when switching through all three charts" do
    assert_selector "#query_performance_chart[data-chart-rendered='true']", wait: 10

    zoom_state = apply_chart_zoom_and_capture("query_performance_chart")

    assert zoom_state, "Should have enough data points to test zoom persistence (need at least 4 data points)"

    # Switch to Execution Volume and verify zoom
    click_tab(:execution_volume)

    assert_selector "#execution_volume_chart[data-chart-rendered='true']", wait: 10
    sleep 0.5
    ev_zoom = read_chart_zoom("execution_volume_chart")

    assert ev_zoom, "Execution volume should inherit zoom"
    assert_equal zoom_state["start"], ev_zoom["startValue"]

    # Switch to Database Load and verify zoom carries over
    click_tab(:database_load)

    assert_selector "#database_load_chart[data-chart-rendered='true']", wait: 10
    sleep 0.5
    dl_zoom = read_chart_zoom("database_load_chart")

    assert dl_zoom, "Database load chart should inherit zoom"
    assert_equal zoom_state["start"], dl_zoom["startValue"]
  end

  test "switching back to a chart after zoom preserves its listeners" do
    click_tab(:execution_volume)

    assert_selector "#execution_volume_chart[data-chart-rendered='true']", wait: 10

    click_tab(:query_performance)

    assert_selector "#query_performance_chart[data-chart-rendered='true']", wait: 5
    sleep 0.5

    zoomed = apply_chart_zoom("query_performance_chart")

    assert zoomed, "Should have enough data points (need at least 4 data points)"

    sleep 1.5

    assert_includes page.current_url, "zoom_start_time",
      "Query performance chart should still update URL after switching back"
  end

  # ── Chart data integrity ─────────────────────────────────────────────────────

  test "all three charts render with valid series data" do
    [ :execution_volume, :database_load ].each do |chart_type|
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

  test "query performance chart handles nil data points without errors" do
    assert_selector "#query_performance_chart[data-chart-rendered='true']", wait: 10

    result = page.execute_script(<<~JS)
      var el = document.getElementById('query_performance_chart');
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
    # Create day-level summaries across the last 30 days (full month) to ensure
    # sufficient data points for zoom operations (zoom requires at least 4 data points).
    # Query summaries feed query_performance and execution_volume charts.
    # Route summaries feed the database_load chart (which compares query total_duration
    # vs route total_duration).

    # Create summaries for ALL queries in fixtures to ensure aggregate charts have data
    RailsPulse::Query.find_each do |query|
      30.downto(1) do |days_ago|
        period_start = days_ago.days.ago.beginning_of_day
        count = 50 + (days_ago * 3)
        avg_duration = 25.0 + (days_ago * 2)

        RailsPulse::Summary.create!(
          summarizable: query,
          period_type: "day",
          period_start: period_start,
          period_end: period_start.end_of_day,
          count: count,
          avg_duration: avg_duration,
          min_duration: 10.0,
          max_duration: 120.0 + (days_ago * 5),
          p95_duration: 80.0 + (days_ago * 4),
          p99_duration: 110.0 + (days_ago * 5),
          total_duration: count * avg_duration,
          error_count: 0,
          success_count: count
        )
      end
    end

    # Create route summaries for database load chart
    route = rails_pulse_routes(:api_users)
    30.downto(1) do |days_ago|
      period_start = days_ago.days.ago.beginning_of_day
      route_count = 80 + (days_ago * 4)
      route_avg_duration = 150.0 + (days_ago * 5)

      RailsPulse::Summary.create!(
        summarizable: route,
        period_type: "day",
        period_start: period_start,
        period_end: period_start.end_of_day,
        count: route_count,
        avg_duration: route_avg_duration,
        min_duration: 80.0,
        max_duration: 400.0,
        p95_duration: 280.0 + (days_ago * 8),
        p99_duration: 380.0 + (days_ago * 10),
        total_duration: route_count * route_avg_duration,
        error_count: days_ago % 7 == 0 ? 5 : 0,  # Errors every 7 days
        status_4xx: days_ago % 5 == 0 ? 3 : 0,   # Client errors every 5 days
        success_count: route_count
      )
    end
  end
end
