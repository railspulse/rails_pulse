require "test_helper"

class QueriesIndexPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_queries, :rails_pulse_summaries

  test "queries index page loads with all major sections" do
    assert_page_loads "/queries"
    assert_metric_cards_present(count: 3)
    assert_chart_renders "query_performance_chart"
    assert_table_has_data
  end

  test "chart zoom updates table" do
    visit_rails_pulse_path "/queries"

    assert_chart_renders "query_performance_chart"

    # Test chart zoom Stimulus behavior
    page.execute_script(<<~JS)
      var el = document.querySelector('#query_performance_chart');
      var chart = echarts.getInstanceByDom(el);
      var dataLen = chart.getOption().xAxis[0].data.length;
      var start = Math.floor(dataLen * 0.25);
      var end = Math.floor(dataLen * 0.75);
      chart.dispatchAction({ type: 'dataZoom', startValue: start, endValue: end });
    JS

    sleep 1.5  # Wait for debounced zoom change

    assert_includes current_url, "zoom_start_time"
    assert_includes current_url, "zoom_end_time"
  end
end
