require "test_helper"

class RoutesChartSwitcherTest < ApplicationSystemTestCase
  fixtures :rails_pulse_routes, :rails_pulse_requests, :rails_pulse_summaries

  CHART_IDS = {
    response_time: "response_time_percentiles_chart",
    request_rate: "request_rate_chart",
    error_rate: "error_rate_chart"
  }.freeze

  def setup
    super
    create_chart_summaries
    visit_rails_pulse_path "/routes?q[period_start_range]=last_30_days"
    page.has_selector?("#response_time_percentiles_chart[data-chart-rendered='true']", wait: 10)
  end

  # ── Default state ────────────────────────────────────────────────────────────

  test "default state is correct" do
    assert_chart_container_visible(:response_time)
    assert_chart_container_hidden(:request_rate)
    assert_chart_container_hidden(:error_rate)

    assert_tab_active(:response_time)
    assert_tab_inactive(:request_rate)
    assert_tab_inactive(:error_rate)

    assert_toggles_visible(:response_time)
    assert_toggles_hidden(:error_rate)
  end

  # ── Tab switching ────────────────────────────────────────────────────────────

  test "switching tabs shows correct chart, updates active state and series toggles" do
    click_tab(:request_rate)

    assert_selector "#request_rate_chart[data-chart-rendered='true']", wait: 10

    assert_chart_container_visible(:request_rate)
    assert_chart_container_hidden(:response_time)
    assert_chart_container_hidden(:error_rate)
    assert_tab_active(:request_rate)
    assert_tab_inactive(:response_time)
    assert_toggles_hidden(:response_time)
    assert_toggles_hidden(:error_rate)

    click_tab(:error_rate)

    assert_selector "#error_rate_chart[data-chart-rendered='true']", wait: 10

    assert_chart_container_visible(:error_rate)
    assert_chart_container_hidden(:response_time)
    assert_chart_container_hidden(:request_rate)
    assert_tab_active(:error_rate)
    assert_tab_inactive(:request_rate)
    assert_toggles_visible(:error_rate)
    assert_toggles_hidden(:response_time)

    click_tab(:response_time)

    assert_selector "#response_time_percentiles_chart[data-chart-rendered='true']", wait: 5

    assert_tab_active(:response_time)
    assert_toggles_visible(:response_time)
    assert_toggles_hidden(:error_rate)
  end

  # ── Chart data integrity ─────────────────────────────────────────────────────

  test "all three charts render with valid series data" do
    [ :request_rate, :error_rate ].each do |chart_type|
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
      return { rendered: true, totalPoints: allPoints.length };
    JS

    assert result["rendered"], "Chart should render successfully"
    assert_operator result["totalPoints"], :>, 0, "Chart should have data points"
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

  # ── Test data ────────────────────────────────────────────────────────────────

  def create_chart_summaries
    route = rails_pulse_routes(:api_users)

    30.downto(1) do |days_ago|
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
        error_count: days_ago % 7 == 0 ? 5 : 0,
        status_4xx: days_ago % 5 == 0 ? 3 : 0,
        success_count: 50 + (days_ago * 3)
      )
    end
  end
end
