require "test_helper"

class ChartTableConcernTest < ActionController::TestCase
  class TestController < ActionController::Base
    include ChartTableConcern

    # Minimal implementation of required abstract methods for testing
    def chart_model; RailsPulse::Summary; end
    def table_model; RailsPulse::Summary; end
    def chart_class; RailsPulse::Routes::Charts::ResponseTimePercentiles; end
    def build_chart_ransack_params(ransack_params); {}; end
    def build_table_ransack_params(ransack_params); {}; end
    def default_table_sort; "avg_duration desc"; end
    def build_table_results; RailsPulse::Summary.none; end
  end

  setup do
    @controller = TestController.new
    @controller.stubs(:turbo_frame_request?).returns(false)
  end

  test "has_meaningful_data? returns true for new multi-series chart format with data" do
    @controller.instance_variable_set(:@chart_data, {
      labels: [ 1000, 2000, 3000 ],
      series: [
        { name: "P95", data: [ 100, 200, 300 ] },
        { name: "P99", data: [ 150, 250, 350 ] }
      ]
    })
    @controller.instance_variable_set(:@table_data, [])

    assert @controller.send(:has_meaningful_data?)
  end

  test "has_meaningful_data? returns false for new multi-series chart format with all zeros" do
    @controller.instance_variable_set(:@chart_data, {
      labels: [ 1000, 2000, 3000 ],
      series: [
        { name: "P95", data: [ 0, 0, 0 ] },
        { name: "P99", data: [ 0, 0, 0 ] }
      ]
    })
    @controller.instance_variable_set(:@table_data, [])

    refute @controller.send(:has_meaningful_data?)
  end

  test "has_meaningful_data? returns true for old simple chart format with data" do
    @controller.instance_variable_set(:@chart_data, {
      1000 => 100.0,
      2000 => 200.0,
      3000 => 300.0
    })
    @controller.instance_variable_set(:@table_data, [])

    assert @controller.send(:has_meaningful_data?)
  end

  test "has_meaningful_data? returns false for old simple chart format with all zeros" do
    @controller.instance_variable_set(:@chart_data, {
      1000 => 0.0,
      2000 => 0.0,
      3000 => 0.0
    })
    @controller.instance_variable_set(:@table_data, [])

    refute @controller.send(:has_meaningful_data?)
  end

  test "has_meaningful_data? returns true when table has data even with empty chart" do
    @controller.instance_variable_set(:@chart_data, { labels: [], series: [] })
    @controller.instance_variable_set(:@table_data, [ { id: 1 } ])

    assert @controller.send(:has_meaningful_data?)
  end
end
