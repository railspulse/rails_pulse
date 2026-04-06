module RailsPulse
  module ChartHelper
    # Main chart rendering method - unified API for all chart types
    # Uses Stimulus controller to handle chart initialization
    def render_stimulus_chart(data, type:, **options)
      chart_id = options[:id] || "rails-pulse-chart-#{SecureRandom.hex(8)}"
      height = options[:height] || "400px"
      width = options[:width] || "100%"
      theme = options[:theme] || "railspulse"
      chart_options = options[:options] || {}

      # Build data attributes for Stimulus
      stimulus_data = {
        controller: "rails-pulse--chart",
        rails_pulse__chart_type_value: type,
        rails_pulse__chart_data_value: data.to_json,
        rails_pulse__chart_options_value: chart_options.to_json,
        rails_pulse__chart_theme_value: theme
      }

      content_tag(:div, "",
        id: chart_id,
        style: "height: #{height}; width: #{width};",
        data: stimulus_data
      )
    end

    # Base chart options shared across all chart types
    def base_chart_options(units: nil, zoom: false)
      {
        tooltip: {
          trigger: "axis",
          axisPointer: { type: "shadow" },
          formatter: "tooltip_with_timestamp"
        },
        toolbox: {
          feature: { saveAsImage: { show: false } }
        },
        xAxis: {
          axisLine: { show: false },
          axisTick: { show: false },
          axisLabel: {
            formatter: "timestamp_to_date"
          }
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

    def bar_chart_options(units: nil, zoom: false, chart_start: 0, chart_end: 100, zoom_start: nil, zoom_end: nil, chart_data: nil)
      options = base_chart_options(units: units, zoom: zoom).deep_merge({
        series: {
          itemStyle: { borderRadius: [ 5, 5, 5, 5 ] }
        }
      })

      apply_zoom_configuration(options, zoom, zoom_start, zoom_end, chart_data)

      options
    end

    def line_chart_options(units: nil, zoom: false, chart_start: 0, chart_end: 100, zoom_start: nil, zoom_end: nil, chart_data: nil)
      options = base_chart_options(units: units, zoom: zoom).deep_merge({
        series: {
          smooth: true,
          lineStyle: { width: 3 },
          symbol: "circle",
          symbolSize: 8
        }
      })

      apply_zoom_configuration(options, zoom, zoom_start, zoom_end, chart_data)

      options
    end

    def sparkline_chart_options
      # Compact sparkline columns that fill the canvas with no axes/labels/gaps
      base_chart_options.deep_merge({
        tooltip: {
          trigger: "axis",
          axisPointer: { type: "shadow" },
          formatter: "sparkline_tooltip"
        },
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
        # Handle both old format { timestamp => value } and new format { labels: [...], series: [...] }
        chart_timestamps = if chart_data.is_a?(Hash) && chart_data[:labels].present?
          # New multi-series chart format - labels are timestamps in milliseconds
          chart_data[:labels]
        elsif chart_data.is_a?(Hash)
          # Old format - keys are timestamps
          chart_data.keys.select { |k| k.is_a?(Numeric) }
        else
          []
        end

        # Convert zoom parameters to integers (timestamps)
        zoom_start_int = zoom_start.respond_to?(:to_i) ? zoom_start.to_i : zoom_start
        zoom_end_int = zoom_end.respond_to?(:to_i) ? zoom_end.to_i : zoom_end

        if chart_timestamps.any?
          closest_start = chart_timestamps.min_by { |ts| (ts.to_i - zoom_start_int.to_i).abs }
          closest_end = chart_timestamps.min_by { |ts| (ts.to_i - zoom_end_int.to_i).abs }

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
