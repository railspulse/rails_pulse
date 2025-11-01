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
    opts = bar_chart_options(units: "ms", zoom: false,
                             xaxis_formatter: "formatX",
                             tooltip_formatter: "formatT")

    assert_equal [ 5, 5, 5, 5 ], opts[:series][:itemStyle][:borderRadius]
    assert_equal "__FUNCTION_START__formatT__FUNCTION_END__", opts[:tooltip][:formatter]
  end

  test "line_chart_options deep merges series and applies formatters" do
    opts = line_chart_options(units: "ms", zoom: false,
                              xaxis_formatter: "formatX",
                              tooltip_formatter: "formatT")

    assert opts[:series][:smooth]
    assert_equal 3, opts[:series][:lineStyle][:width]
    assert_equal "circle", opts[:series][:symbol]
    assert_equal "__FUNCTION_START__formatT__FUNCTION_END__", opts[:tooltip][:formatter]
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

  test "render_stimulus_chart generates Stimulus-compatible div" do
    data = { 100 => 1, 200 => 2, 300 => 3 }
    html = render_stimulus_chart(data, type: "bar", height: "300px")

    assert_match(/data-controller="rails-pulse--chart"/, html)
    assert_match(/data-rails-pulse--chart-type-value="bar"/, html)
    assert_match(/data-rails-pulse--chart-data-value/, html)
    assert_match(/style="height: 300px/, html)
  end

  test "render_stimulus_chart serializes data correctly" do
    data = { 100 => 1, 200 => 2 }
    html = render_stimulus_chart(data, type: "bar")

    # Extract data attribute value
    doc = Nokogiri::HTML(html)
    data_attr = doc.at_css("[data-rails-pulse--chart-data-value]")
    parsed_data = JSON.parse(data_attr["data-rails-pulse--chart-data-value"])

    assert_equal({ "100" => 1, "200" => 2 }, parsed_data)
  end

  test "render_stimulus_chart supports different chart types" do
    data = { 100 => 1, 200 => 2 }

    bar_html = render_stimulus_chart(data, type: "bar")
    line_html = render_stimulus_chart(data, type: "line")

    assert_match(/data-rails-pulse--chart-type-value="bar"/, bar_html)
    assert_match(/data-rails-pulse--chart-type-value="line"/, line_html)
  end

  test "render_stimulus_chart includes options as JSON" do
    data = { 100 => 1, 200 => 2 }
    options = bar_chart_options(units: "ms")
    html = render_stimulus_chart(data, type: "bar", options: options)

    assert_match(/data-rails-pulse--chart-options-value/, html)

    # Extract and parse options
    doc = Nokogiri::HTML(html)
    options_attr = doc.at_css("[data-rails-pulse--chart-options-value]")
    parsed_options = JSON.parse(options_attr["data-rails-pulse--chart-options-value"])

    assert parsed_options["series"]
    assert parsed_options["tooltip"]
  end

  test "render_stimulus_chart generates unique IDs" do
    data = { 100 => 1 }
    html1 = render_stimulus_chart(data, type: "bar")
    html2 = render_stimulus_chart(data, type: "bar")

    # Extract IDs
    id1 = html1.match(/id="([^"]+)"/)[1]
    id2 = html2.match(/id="([^"]+)"/)[1]

    refute_equal id1, id2, "Chart IDs should be unique"
  end

  test "render_stimulus_chart accepts custom ID" do
    data = { 100 => 1 }
    html = render_stimulus_chart(data, type: "bar", id: "custom-chart-id")

    assert_match(/id="custom-chart-id"/, html)
  end

  test "render_stimulus_chart sets theme value" do
    data = { 100 => 1 }
    html = render_stimulus_chart(data, type: "bar", theme: "dark")

    assert_match(/data-rails-pulse--chart-theme-value="dark"/, html)
  end

  test "render_stimulus_chart uses default theme when not specified" do
    data = { 100 => 1 }
    html = render_stimulus_chart(data, type: "bar")

    assert_match(/data-rails-pulse--chart-theme-value="railspulse"/, html)
  end
end
