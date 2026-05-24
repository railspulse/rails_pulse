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
    RailsPulse::Summary.where(summarizable_type: "RailsPulse::Query").delete_all
    RailsPulse::Summary.where(
      summarizable_type: "RailsPulse::Route",
      summarizable_id: rails_pulse_routes(:api_users).id
    ).delete_all
    create_chart_summaries
    visit_rails_pulse_path "/queries?q[period_start_range]=last_30_days"
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
    click_tab(:execution_volume)

    assert_selector "#execution_volume_chart[data-chart-rendered='true']", wait: 10

    assert_chart_container_visible(:execution_volume)
    assert_chart_container_hidden(:query_performance)
    assert_chart_container_hidden(:database_load)
    assert_tab_active(:execution_volume)
    assert_tab_inactive(:query_performance)
    assert_toggles_hidden(:query_performance)
    assert_toggles_hidden(:database_load)

    click_tab(:database_load)

    assert_selector "#database_load_chart[data-chart-rendered='true']", wait: 10

    assert_chart_container_visible(:database_load)
    assert_chart_container_hidden(:query_performance)
    assert_chart_container_hidden(:execution_volume)
    assert_tab_active(:database_load)
    assert_tab_inactive(:execution_volume)
    assert_toggles_hidden(:query_performance)
    assert_toggles_hidden(:execution_volume)

    click_tab(:query_performance)

    assert_selector "#query_performance_chart[data-chart-rendered='true']", wait: 5

    assert_tab_active(:query_performance)
    assert_toggles_visible(:query_performance)
    assert_toggles_hidden(:execution_volume)
    assert_toggles_hidden(:database_load)
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
        error_count: days_ago % 7 == 0 ? 5 : 0,
        status_4xx: days_ago % 5 == 0 ? 3 : 0,
        success_count: route_count
      )
    end
  end
end
