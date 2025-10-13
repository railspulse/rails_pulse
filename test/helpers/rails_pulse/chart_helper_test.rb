require "test_helper"

class RailsPulse::ChartHelperTest < ActionView::TestCase
  include RailsPulse::ChartHelper

  test "base_chart_options sets defaults with units and zoom" do
    opts = base_chart_options(units: "ms", zoom: true)

    assert_equal "{value} ms", opts[:yAxis][:axisLabel][:formatter]
    assert_equal "60", opts[:grid][:bottom]
    assert opts[:animation]
  end

  test "bar_chart_options deep merges series and applies formatters" do
    RailsCharts.expects(:js).with("formatT").returns("JS Tooltip").once
    RailsCharts.expects(:js).with("formatX").returns("JS XAxis").once

    opts = bar_chart_options(units: "ms", zoom: false,
                             xaxis_formatter: "formatX",
                             tooltip_formatter: "formatT")

    assert_equal [ 5, 5, 5, 5 ], opts[:series][:itemStyle][:borderRadius]
    assert_equal "JS Tooltip", opts[:tooltip][:formatter]
  end

  test "line_chart_options deep merges series and applies formatters" do
    RailsCharts.expects(:js).with("formatT").returns("JS Tooltip")
    RailsCharts.expects(:js).with("formatX").returns("JS XAxis")

    opts = line_chart_options(units: "ms", zoom: false,
                              xaxis_formatter: "formatX",
                              tooltip_formatter: "formatT")

    assert opts[:series][:smooth]
    assert_equal 3, opts[:series][:lineStyle][:width]
    assert_equal "circle", opts[:series][:symbol]
    assert_equal "JS Tooltip", opts[:tooltip][:formatter]
  end

  test "sparkline_chart_options hides axes and grid" do
    opts = sparkline_chart_options

    assert_equal "bar", opts[:series][:type]
    refute opts[:yAxis][:show]
  end

  test "area_chart_options sets symbol and line style" do
    opts = area_chart_options

    assert_equal "roundRect", opts[:series][:symbol]
    assert_equal 8, opts[:series][:symbolSize]
  end

  test "bar_chart_options applies zoom configuration with chart_data" do
    chart_data = {
      100 => { value: 1 },
      200 => { value: 2 },
      300 => { value: 3 }
    }

    opts = bar_chart_options(units: "ms", zoom: true,
                             zoom_start: 110, zoom_end: 290,
                             chart_data: chart_data)

    assert_kind_of Array, opts[:dataZoom]
    slider = opts[:dataZoom].first

    assert_equal 0, slider[:startValue]
    assert_equal 2, slider[:endValue]
  end

  test "line_chart_options sets dataZoom when zoom true and chart_data empty" do
    opts = line_chart_options(zoom: true, chart_data: {})

    assert_equal "slider", opts[:dataZoom].first[:type]
  end
end
