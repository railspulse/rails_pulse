module RailsPulse
  module ChartHelper
    # Renders a bar chart using eCharts directly (no rails_charts gem dependency)
    def rails_pulse_bar_chart(data, options = {})
      chart_id = options[:id] || "rails-pulse-chart-#{SecureRandom.hex(8)}"
      height = options[:height] || "400px"
      width = options[:width] || "100%"
      theme = options[:theme] || "railspulse"
      chart_options = options[:options] || {}

      # Prepare data for eCharts
      # Data comes in as Hash: { "label1" => value1, "label2" => value2 }
      # or { timestamp => { value: 123.45 } }
      # Keep timestamps as numeric values, convert other keys to strings
      labels = data.keys.map { |k| k.is_a?(Numeric) ? k : k.to_s }
      values = data.values.map { |v| v.is_a?(Hash) ? (v[:value] || v["value"]) : v }

      # Start with the chart_options which has all the styling
      echarts_config = chart_options.deep_dup

      # Now set/override the data-related properties
      echarts_config[:xAxis] ||= {}
      echarts_config[:xAxis][:type] = 'category'
      echarts_config[:xAxis][:data] = labels

      echarts_config[:yAxis] ||= {}
      echarts_config[:yAxis][:type] = 'value'

      # Handle series: if it's a hash (from bar_chart_options), convert to array format
      # and merge with data
      if echarts_config[:series].is_a?(Hash)
        series_config = echarts_config[:series]
        echarts_config[:series] = [{
          type: 'bar',
          data: values
        }.merge(series_config)]
      else
        # If it's already an array or nil, create the series array with data
        echarts_config[:series] = [{
          type: 'bar',
          data: values
        }]
      end

      # Render chart container + initialization script
      render_chart_html(chart_id, height, width, theme, echarts_config)
    end

    # Base chart options shared across all chart types
    def base_chart_options(units: nil, zoom: false)
      {
        tooltip: {
          trigger: "axis",
          axisPointer: { type: "shadow" }
        },
        toolbox: {
          feature: { saveAsImage: { show: false } }
        },
        xAxis: {
          axisLine: { show: false },
          axisTick: { show: false }
        },
        yAxis: {
          splitArea: { show: false },
          axisLabel: {
            formatter: "{value} #{units}"
          }
        },
        grid: {
          left: "0",
          right: "2%",
          bottom: (zoom ? "60" : "0"),
          top: "10%",
          containLabel: true
        },
        animation: true
      }
    end

    def bar_chart_options(units: nil, zoom: false, chart_start: 0, chart_end: 100, xaxis_formatter: nil, tooltip_formatter: nil, zoom_start: nil, zoom_end: nil, chart_data: nil)
      options = base_chart_options(units: units, zoom: zoom).deep_merge({
        series: {
          itemStyle: { borderRadius: [ 5, 5, 5, 5 ] }
        }
      })

      apply_tooltip_formatter(options, tooltip_formatter)
      apply_xaxis_formatter(options, xaxis_formatter)
      apply_zoom_configuration(options, zoom, zoom_start, zoom_end, chart_data)

      options
    end

    def line_chart_options(units: nil, zoom: false, chart_start: 0, chart_end: 100, xaxis_formatter: nil, tooltip_formatter: nil, zoom_start: nil, zoom_end: nil, chart_data: nil)
      options = base_chart_options(units: units, zoom: zoom).deep_merge({
        series: {
          smooth: true,
          lineStyle: { width: 3 },
          symbol: "circle",
          symbolSize: 8
        }
      })

      apply_tooltip_formatter(options, tooltip_formatter)
      apply_xaxis_formatter(options, xaxis_formatter)
      apply_zoom_configuration(options, zoom, zoom_start, zoom_end, chart_data)

      options
    end

    def sparkline_chart_options
      # Compact sparkline columns that fill the canvas with no axes/labels/gaps
      base_chart_options.deep_merge({
        series: {
          type: "bar",
          itemStyle: { borderRadius: [ 2, 2, 0, 0 ] },
          barCategoryGap: "10%",
          barGap: "0%"
        },
        yAxis: { show: false, splitLine: { show: false } },
        xAxis: {
          type: "category",
          boundaryGap: true,
          axisLine: { show: false },
          axisTick: { show: false },
          splitLine: { show: false },
          axisLabel: { show: false }
        },
        grid: { left: 0, right: 0, top: 0, bottom: 0, containLabel: false, show: false }
      })
    end

    def area_chart_options
      base_chart_options.deep_merge({
        series: {
          smooth: true,
          lineStyle: { width: 3 },
          symbol: "roundRect",
          symbolSize: 8
        }
      })
    end

    private

    # Wraps JavaScript function strings for later processing
    def js_function(func_string)
      # Mark this as a JavaScript function for later processing
      "__FUNCTION_START__#{func_string}__FUNCTION_END__"
    end

    # Deep merge chart options, handling nested hashes correctly
    def deep_merge_chart_options(base, custom)
      merged = base.deep_dup

      custom.each do |key, value|
        if merged[key].is_a?(Hash) && value.is_a?(Hash)
          merged[key] = deep_merge_chart_options(merged[key], value)
        else
          merged[key] = value
        end
      end

      merged
    end

    # Renders the HTML for chart container and initialization script
    def render_chart_html(chart_id, height, width, theme, config)
      config_json = chart_config_to_json(config)

      content_tag(:div, '',
        id: chart_id,
        style: "height: #{height}; width: #{width};"
      ) +
      content_tag(:script, nonce: content_security_policy_nonce) do
        <<~JAVASCRIPT.html_safe
          (function() {
            // Wait for echarts to be available
            var retryCount = 0;
            var maxRetries = 100; // 5 seconds max

            function initChart() {
              if (typeof echarts === 'undefined') {
                retryCount++;
                if (retryCount >= maxRetries) {
                  console.error('[RailsPulse] echarts not loaded after 5 seconds for #{chart_id}');
                  return;
                }
                setTimeout(initChart, 50);
                return;
              }

              // Initialize global chart registry if not exists
              if (!window.RailsPulse) {
                window.RailsPulse = {};
              }
              if (!window.RailsPulse.charts) {
                window.RailsPulse.charts = {};
              }

              var chartDom = document.getElementById('#{chart_id}');
              if (!chartDom) {
                console.error('[RailsPulse] Chart container not found: #{chart_id}');
                return;
              }

              try {
                var chart = echarts.init(chartDom, '#{theme}');
                var option = #{config_json};
                chart.setOption(option);

                // Store chart instance in global registry for Stimulus controllers
                window.RailsPulse.charts['#{chart_id}'] = chart;

                // Dispatch custom event to notify Stimulus controllers
                document.dispatchEvent(new CustomEvent('chart:rendered', {
                  detail: {
                    containerId: '#{chart_id}',
                    chart: chart
                  }
                }));

                // Responsive resize
                window.addEventListener('resize', function() {
                  chart.resize();
                });

                // Mark as rendered for tests
                chartDom.setAttribute('data-chart-rendered', 'true');
              } catch (error) {
                console.error('[RailsPulse] Error initializing chart #{chart_id}:', error);
              }
            }

            // Start initialization (will wait for echarts if needed)
            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', initChart);
            } else {
              initChart();
            }
          })();
        JAVASCRIPT
      end
    end

    # Convert config to JSON, preserving JavaScript function strings
    def chart_config_to_json(config)
      # Convert config to JSON, but preserve JavaScript function strings
      # This handles the js_function() wrapped functions
      JSON.generate(config).gsub(/"__FUNCTION_START__(.*?)__FUNCTION_END__"/m) do
        # Extract the function string and properly unescape it
        # The function string has been JSON-encoded, so we need to decode it
        function_str = $1
        # Unescape the JSON escaping (order matters!)
        function_str = function_str.gsub('\\"', '"')      # Unescape quotes
        function_str = function_str.gsub('\\n', "\n")     # Unescape newlines
        function_str = function_str.gsub('\\t', "\t")     # Unescape tabs
        function_str = function_str.gsub('\\r', "\r")     # Unescape carriage returns
        function_str = function_str.gsub('\\\\', '\\')    # Unescape backslashes last
        function_str
      end
    end

    def apply_tooltip_formatter(options, tooltip_formatter)
      return unless tooltip_formatter.present?

      options[:tooltip][:formatter] = js_function(tooltip_formatter)
    end

    def apply_xaxis_formatter(options, xaxis_formatter)
      return unless xaxis_formatter.present?

      options[:xAxis][:axisLabel] ||= { formatter: js_function(xaxis_formatter) }
    end

    def apply_zoom_configuration(options, zoom, zoom_start, zoom_end, chart_data)
      return unless zoom

      zoom_config = {
        type: "slider",
        height: 20,
        bottom: 10,
        showDetail: false
      }

      # Initialize zoom range if zoom parameters are provided
      if zoom_start.present? && zoom_end.present? && chart_data.present?
        # Find closest matching timestamps in the actual chart data
        # Chart data is a hash like: { 1234567890 => { value: 123.45 } }
        chart_timestamps = chart_data.keys

        # Convert zoom parameters to integers (timestamps)
        zoom_start_int = zoom_start.respond_to?(:to_i) ? zoom_start.to_i : zoom_start
        zoom_end_int = zoom_end.respond_to?(:to_i) ? zoom_end.to_i : zoom_end

        if chart_timestamps.any?
          closest_start = chart_timestamps.min_by { |ts| (ts - zoom_start_int).abs }
          closest_end = chart_timestamps.min_by { |ts| (ts - zoom_end_int).abs }

          # Find the array indices of these timestamps
          start_index = chart_timestamps.index(closest_start)
          end_index = chart_timestamps.index(closest_end)

          # Use array indices for dataZoom instead of timestamp values
          zoom_config[:startValue] = start_index
          zoom_config[:endValue] = end_index
        end
      end

      options[:dataZoom] = [
        zoom_config,
        { type: "inside" }
      ]
    end
  end
end
