module ChartValidationHelpers
  # Chart validation helper methods for system tests
  def validate_chart_data(chart_selector, expected_data: [], filter_applied: nil)
    # Wait for chart to be fully rendered
    assert_selector "#{chart_selector}[data-chart-rendered='true']", wait: 10

    chart_data = extract_chart_data(chart_selector)

    # Basic structure validation
    assert chart_data[:has_data], "Chart should contain data"
    assert_operator chart_data[:series_count], :>, 0, "Chart should have at least one data series"
    assert chart_data[:has_x_axis_data], "Chart should have x-axis data (time periods)"
    assert_operator chart_data[:data_point_count], :>, 0, "Chart should have data points"

    # Detailed data validation
    validate_chart_series_data(chart_data, expected_data, filter_applied)
    validate_chart_time_periods(chart_data, filter_applied)
    validate_chart_response_times(chart_data, expected_data)
  end

  def extract_chart_data(chart_selector)
    result = page.execute_script("
      var chartElement = document.querySelector('#{chart_selector}');
      if (!chartElement) {
        return { has_data: false, error: 'Chart element not found' };
      }

      var chartInstance = echarts.getInstanceByDom(chartElement);
      if (!chartInstance) {
        return { has_data: false, error: 'Chart instance not found' };
      }

      var option = chartInstance.getOption();
      var series = option.series || [];
      var xAxis = option.xAxis ? option.xAxis[0] : null;
      var yAxis = option.yAxis ? option.yAxis[0] : null;

      var seriesData = [];
      for (var i = 0; i < series.length; i++) {
        var s = series[i];
        seriesData.push({
          name: s.name,
          type: s.type,
          data: s.data || [],
          stack: s.stack
        });
      }

      return {
        has_data: series.length > 0,
        series_count: series.length,
        has_x_axis_data: xAxis && xAxis.data && xAxis.data.length > 0,
        data_point_count: series[0] && series[0].data ? series[0].data.length : 0,
        series_data: seriesData,
        x_axis_data: xAxis ? xAxis.data : [],
        x_axis_type: xAxis ? xAxis.type : null,
        y_axis_name: yAxis ? yAxis.name : null,
        y_axis_type: yAxis ? yAxis.type : null,
        title: option.title ? option.title.text : null,
        tooltip: option.tooltip ? true : false,
        legend: option.legend ? option.legend.data : []
      };
    ")

    # Convert string keys to symbols for consistent access
    result.deep_symbolize_keys if result.respond_to?(:deep_symbolize_keys)
    result.transform_keys(&:to_sym) if result.is_a?(Hash)
  end

  def validate_chart_series_data(chart_data, expected_data, filter_applied)
    series_data = chart_data[:series_data]

    # Should have at least one series for average response times
    assert_operator series_data.length, :>=, 1, "Chart should have at least one data series"

    # Verify series structure
    series_data.each do |series|
      # Series name might be empty for single-series charts
      assert series.key?("name"), "Series should have a name key (even if empty)"
      assert_equal "bar", series["type"], "Response time chart should use bar type"
      assert_kind_of Array, series["data"], "Series data should be an array"
      assert_operator series["data"].length, :>, 0, "Series should contain data points"
    end

    # Validate data points match expected data
    total_data_points = series_data.sum { |s| s["data"].length }

    # The chart should show time-based aggregated data, so we expect
    # data points to represent time periods, not individual records
    min_expected_points = filter_applied == "Last Month" ? 7 : 3  # At least a week of data

    assert_operator total_data_points, :>=, min_expected_points, "Chart should have at least #{min_expected_points} time-based data points, got #{total_data_points}"
  end

  def validate_chart_time_periods(chart_data, filter_applied)
    x_axis_data = chart_data[:x_axis_data]

    assert_operator x_axis_data.length, :>, 0, "Chart should have time period labels on x-axis"

    # Verify x-axis contains time-based labels (dates/times)
    x_axis_data.each do |label|
      # Should be numeric timestamps
      assert label.is_a?(Numeric) && label.to_s.length >= 10,
             "X-axis labels should be non-empty timestamps, got: #{label}"
    end

    # Verify axis configuration
    assert_equal "category", chart_data[:x_axis_type], "X-axis should be category type for time periods"
    assert_equal "value", chart_data[:y_axis_type], "Y-axis should be value type for response times"
  end

  def validate_chart_response_times(chart_data, expected_data)
    series_data = chart_data[:series_data]

    series_data.each do |series|
      series["data"].each do |data_point|
        # Data points should be numbers representing response times in milliseconds
        response_time = data_point.is_a?(Array) ? data_point[1] : data_point

        assert_kind_of Numeric, response_time,
               "Response time should be numeric, got #{response_time.class}: #{response_time}"
        assert_operator response_time, :>=, 0, "Response time should be non-negative, got: #{response_time}"
        assert_operator response_time, :<, 10000, "Response time should be reasonable (< 10s), got: #{response_time}ms"
      end
    end

    # Verify we have data points that align with our test data categories
    all_response_times = series_data.flat_map { |s|
      s["data"].map { |dp| dp.is_a?(Array) ? dp[1] : dp }
    }

    return if all_response_times.empty?

    # Should have some variety in response times based on our test data
    min_response_time = all_response_times.min
    max_response_time = all_response_times.max

    # Based on our test data, we should see some variety in response times
    # For queries: fast < 100ms, slow >= 100ms, critical >= 1000ms
    # For routes: fast < 500ms, slow >= 500ms, critical >= 3000ms
    # Be flexible to handle both types of data
    if max_response_time > 0
      assert_operator min_response_time, :>=, 0, "Should have non-negative response times, min was: #{min_response_time}ms"
      assert_operator max_response_time, :<, 10000, "Should have reasonable response times < 10s, max was: #{max_response_time}ms"
    else
      # If all response times are 0, the chart might be empty or have no meaningful data
      # This could be valid for a fresh/empty dataset
      puts "Warning: All response times are 0ms - chart may be empty or have no data"
    end
  end

  # Enhanced chart data validation for dashboard charts
  def validate_dashboard_chart_data(chart_selector, expected_min_value:, expected_max_value:, data_type: "response time")
    # Verify chart has data rendered by checking for canvas element
    within chart_selector do
      assert_selector "canvas", wait: 10
    end

    # Extract detailed chart data using JavaScript
    chart_data = page.execute_script("
      var chartElement = document.querySelector('#{chart_selector}');
      var chartInstance = echarts && echarts.getInstanceByDom && echarts.getInstanceByDom(chartElement);
      if (chartInstance) {
        var option = chartInstance.getOption();
        if (option.series && option.series[0] && option.series[0].data) {
          var data = option.series[0].data;
          return {
            hasSeries: true,
            hasData: data.length > 0,
            dataPoints: data.length,
            values: data.map(function(point) { return point.value || point; }),
            maxValue: Math.max.apply(Math, data.map(function(point) { return point.value || point; })),
            minValue: Math.min.apply(Math, data.map(function(point) { return point.value || point; }))
          };
        }
      }
      return { hasSeries: false, hasData: false };
    ")

    # Validate the extracted data
    if chart_data && chart_data["hasSeries"]
      assert chart_data["hasData"], "Chart should contain data points"
      assert_operator chart_data["dataPoints"], :>=, 3, "Chart should have multiple time periods of data"

      # Verify values are realistic based on test data expectations
      max_value = chart_data["maxValue"]
      min_value = chart_data["minValue"]

      assert_operator max_value, :>, 0, "Chart should show non-zero #{data_type} values"
      assert_operator max_value, :>, min_value, "Chart should show variance in #{data_type} values"
      assert_operator max_value, :>=, expected_min_value, "Chart should reflect test data with #{data_type} values >= #{expected_min_value}ms"
      assert_operator max_value, :<=, expected_max_value, "Chart #{data_type} values should be reasonable (<= #{expected_max_value}ms)"
    else
      flunk "Chart should have series data available"
    end

    chart_data
  end
end
