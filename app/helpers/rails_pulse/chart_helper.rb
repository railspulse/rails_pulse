module RailsPulse
  module ChartHelper
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
        animation: false
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

    def apply_tooltip_formatter(options, tooltip_formatter)
      return unless tooltip_formatter.present?

      options[:tooltip][:formatter] = RailsCharts.js(tooltip_formatter)
    end

    def apply_xaxis_formatter(options, xaxis_formatter)
      return unless xaxis_formatter.present?

      options[:xAxis][:axisLabel] ||= { formatter: RailsCharts.js(xaxis_formatter) }
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
