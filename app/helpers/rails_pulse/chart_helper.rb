module RailsPulse
  module ChartHelper
    # Unified method for generating fake time series data
    def fake_time_series(days_back: 14, series_name: nil)
      today = Date.today
      start_date = today - days_back

      data = (start_date..today).each_with_object({}) do |date, hash|
        formatted_date = date.strftime("%b %-d")
        value = rand(3..10)
        hash[formatted_date] = {
          value: value
        }
      end

      # Return as array with series name if provided (area chart), otherwise plain hash
      series_name ? [ { name: series_name, data: data } ] : data
    end

    def fake_sparkline_series(days_back: 14)
      today = Date.today
      start_date = today - days_back

      (start_date..today).each_with_object({}) do |date, hash|
        formatted_date = date.strftime("%b %-d")
        value = rand(3..10)
        hash[formatted_date] = {
          value: value
        }
      end
    end

    def fake_time_distribution_series(days_back: 14)
      fastest = 100
      slowest = 300
      mean = 140 # Center the bell curve around 140
      std_dev = 50 # Adjust the spread of the curve

      (fastest..slowest).step(10).each_with_object({}) do |duration, hash|
        # Generate a value using a Gaussian function
        gaussian = Math.exp(-((duration - mean)**2) / (2.0 * std_dev**2))
        value = (gaussian * 10).round # Scale to a range of 1 to 10
        value = [ [ value, 1 ].max, 10 ].min # Clamp values between 1 and 10
        hash[duration] = {
          value: value
        }
      end
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
        animation: false
      }
    end

    def bar_chart_options(units: nil)
      base_chart_options.deep_merge({
        series: {
          itemStyle: { borderRadius: [ 5, 5, 5, 5 ] }
        }
      })
    end

    def line_chart_options(units: nil, zoom: false, chart_start: 0, chart_end: 100, xaxis_formatter: nil, tooltip_formatter: nil)
      options = base_chart_options(units: units, zoom: zoom).deep_merge({
        series: {
          smooth: true,
          lineStyle: { width: 3 },
          symbol: "circle",
          symbolSize: 8
        }
      })

      if tooltip_formatter.present?
        options[:tooltip][:formatter] = RailsCharts.js(tooltip_formatter)
      end

      if xaxis_formatter.present?
        options[:xAxis][:axisLabel] ||= { formatter: RailsCharts.js(xaxis_formatter) }
      end

      if zoom
        options[:dataZoom] = [
          {
            type: "slider",
            height: 20,
            bottom: 10,
            showDetail: false
          },
          { type: "inside" }
        ]
      end

      options
    end

    def sparkline_chart_options
      base_chart_options.deep_merge({
        series: {
          type: "line",
          smooth: true,
          lineStyle: { width: 2 },
          symbol: "none"
        },
        yAxis: { show: false },
        grid: { left: "0", right: "0", bottom: "0", top: "5" }
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
  end
end
