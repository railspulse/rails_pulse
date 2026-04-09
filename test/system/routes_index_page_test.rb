require "test_helper"

class RoutesIndexPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_routes, :rails_pulse_summaries

  test "routes index page loads with all major sections" do
    assert_page_loads "/routes"
    assert_metric_cards_present(count: 3)
    assert_chart_renders "response_time_percentiles_chart"
    assert_table_has_data
  end

  test "chart zoom updates table" do
    visit_rails_pulse_path "/routes"

    assert_chart_renders "response_time_percentiles_chart"

    # Test chart zoom Stimulus behavior
    page.execute_script(<<~JS)
      var el = document.querySelector('#response_time_percentiles_chart');
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
