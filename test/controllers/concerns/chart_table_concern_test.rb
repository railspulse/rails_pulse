require "test_helper"

class ChartTableConcernTest < ActionController::TestCase
  # Simple test chart class instead of mock
  class TestChartClass
    attr_reader :options

    def initialize(**options)
      @options = options
    end

    def to_chart_data
      { labels: [], series: [ { name: "Test", data: [ 100, 200 ] } ] }
    end
  end

  class TestController < ActionController::Base
    include PaginationConcern
    include SessionFiltersConcern
    include ChartTableConcern

    attr_accessor :params, :session

    def initialize
      super
      @params = ActionController::Parameters.new({})
      @session = {}
    end

    def chart_model; RailsPulse::Summary; end
    def table_model; RailsPulse::Summary; end
    def chart_class; TestChartClass; end
    def chart_definitions; { chart_data: TestChartClass }; end
    def default_table_sort; "avg_duration desc"; end
    def build_table_results; RailsPulse::Summary.none; end
    def summarizable_type; nil; end
    def show_resource_filter; {}; end
    def current_resource; nil; end
    def chart_options; {}; end

    def turbo_frame_request?; false; end
    def action_name; "index"; end
  end

  fixtures :rails_pulse_summaries, :rails_pulse_routes

  setup do
    @controller = TestController.new
  end

  # Existing Tests - Keep These

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

  # New Tests - setup_chart_and_table_data

  test "setup_chart_and_table_data calls setup_chart_data when not turbo frame" do
    @controller.stubs(:turbo_frame_request?).returns(false)
    @controller.expects(:setup_chart_data).once
    @controller.stubs(:setup_table_data)
    @controller.stubs(:meaningful_chart_data?).returns(true)
    @controller.stubs(:has_meaningful_data?).returns(true)

    @controller.send(:setup_chart_and_table_data)
  end

  test "setup_chart_and_table_data skips chart setup for turbo frame requests" do
    @controller.stubs(:turbo_frame_request?).returns(true)
    @controller.expects(:setup_chart_data).never
    @controller.stubs(:setup_table_data)
    @controller.stubs(:has_meaningful_data?).returns(true)

    @controller.send(:setup_chart_and_table_data)
  end

  test "setup_chart_and_table_data always calls setup_table_data" do
    @controller.stubs(:turbo_frame_request?).returns(true)
    @controller.expects(:setup_table_data).once
    @controller.stubs(:has_meaningful_data?).returns(true)

    @controller.send(:setup_chart_and_table_data)
  end

  test "setup_chart_and_table_data sets @has_chart_data" do
    @controller.stubs(:turbo_frame_request?).returns(false)
    @controller.stubs(:setup_chart_data)
    @controller.stubs(:setup_table_data)
    @controller.stubs(:meaningful_chart_data?).returns(true)
    @controller.stubs(:has_meaningful_data?).returns(true)

    @controller.send(:setup_chart_and_table_data)

    assert @controller.instance_variable_defined?(:@has_chart_data)
  end

  test "setup_chart_and_table_data sets @has_data" do
    @controller.stubs(:turbo_frame_request?).returns(false)
    @controller.stubs(:setup_chart_data)
    @controller.stubs(:setup_table_data)
    @controller.stubs(:meaningful_chart_data?).returns(true)
    @controller.stubs(:has_meaningful_data?).returns(true)

    @controller.send(:setup_chart_and_table_data)

    assert @controller.instance_variable_defined?(:@has_data)
  end

  test "setup_chart_and_table_data uses params[:q] or empty hash" do
    q_params = ActionController::Parameters.new({ test: "value" })
    @controller.params = ActionController::Parameters.new({ q: q_params })
    @controller.stubs(:turbo_frame_request?).returns(false)
    @controller.stubs(:meaningful_chart_data?).returns(true)
    @controller.stubs(:has_meaningful_data?).returns(true)

    # The concern calls setup_chart_data and setup_table_data with params[:q]
    @controller.stubs(:setup_chart_data)
    @controller.stubs(:setup_table_data)

    # Should not raise any errors with valid params structure
    assert_nothing_raised do
      @controller.send(:setup_chart_and_table_data)
    end
  end

  # period_type Tests

  test "period_type returns :hour when time_diff_hours <= 25" do
    @controller.instance_variable_set(:@time_diff_hours, 20.0)

    result = @controller.send(:period_type)

    assert_equal :hour, result
  end

  test "period_type returns :day when time_diff_hours > 25" do
    @controller.instance_variable_set(:@time_diff_hours, 30.0)

    result = @controller.send(:period_type)

    assert_equal :day, result
  end

  test "period_type returns :day when time_diff_hours nil" do
    @controller.instance_variable_set(:@time_diff_hours, nil)

    result = @controller.send(:period_type)

    assert_equal :day, result
  end

  # meaningful_chart_data? Tests

  test "meaningful_chart_data? returns false when chart_data not hash with series" do
    @controller.instance_variable_set(:@chart_data, [])

    refute @controller.send(:meaningful_chart_data?)
  end

  test "meaningful_chart_data? excludes SLO series from check" do
    @controller.instance_variable_set(:@chart_data, {
      labels: [ 1000, 2000 ],
      series: [
        { name: "Data", data: [ 0, 0 ] },
        { name: "P95 SLO ", data: [ 100, 200 ] }  # SLO series with data
      ]
    })

    # Should return false because only SLO has data
    refute @controller.send(:meaningful_chart_data?)
  end

  test "meaningful_chart_data? returns true when any non-SLO series has positive data" do
    @controller.instance_variable_set(:@chart_data, {
      labels: [ 1000, 2000 ],
      series: [
        { name: "Data", data: [ 100, 200 ] },
        { name: "P95 SLO ", data: [ 0, 0 ] }
      ]
    })

    assert @controller.send(:meaningful_chart_data?)
  end

  test "meaningful_chart_data? returns false when all non-SLO data is zero" do
    @controller.instance_variable_set(:@chart_data, {
      labels: [ 1000, 2000 ],
      series: [
        { name: "Data", data: [ 0, 0 ] },
        { name: "Other", data: [ 0, 0 ] }
      ]
    })

    refute @controller.send(:meaningful_chart_data?)
  end

  # build_chart_ransack_params Tests

  test "build_chart_ransack_params excludes sort param" do
    ransack_params = { s: "name desc", other: "value" }

    result = @controller.send(:build_chart_ransack_params, ransack_params)

    refute_includes result.keys, :s
    assert_includes result.keys, :other
  end

  test "build_chart_ransack_params adds time filters when times present" do
    @controller.instance_variable_set(:@start_time, 7.days.ago.to_i)
    @controller.instance_variable_set(:@end_time, Time.current.to_i)

    result = @controller.send(:build_chart_ransack_params, {})

    assert_includes result.keys, :period_start_gteq
    assert_includes result.keys, :period_start_lt
    assert_kind_of Time, result[:period_start_gteq]
    assert_kind_of Time, result[:period_start_lt]
  end

  test "build_chart_ransack_params skips time filters when times nil" do
    @controller.instance_variable_set(:@start_time, nil)
    @controller.instance_variable_set(:@end_time, nil)

    result = @controller.send(:build_chart_ransack_params, {})

    refute_includes result.keys, :period_start_gteq
    refute_includes result.keys, :period_start_lt
  end

  test "build_chart_ransack_params adds summarizable_type when present" do
    @controller.stubs(:summarizable_type).returns("RailsPulse::Query")

    result = @controller.send(:build_chart_ransack_params, {})

    assert_equal "RailsPulse::Query", result[:summarizable_type_eq]
  end

  test "build_chart_ransack_params adds avg_duration_gteq when threshold > 0" do
    @controller.instance_variable_set(:@start_duration, 500)

    result = @controller.send(:build_chart_ransack_params, {})

    assert_equal 500, result[:avg_duration_gteq]
  end

  test "build_chart_ransack_params skips duration filter when 0" do
    @controller.instance_variable_set(:@start_duration, 0)

    result = @controller.send(:build_chart_ransack_params, {})

    refute_includes result.keys, :avg_duration_gteq
  end

  test "build_chart_ransack_params adds resource scope for show action" do
    @controller.stubs(:show_action?).returns(true)
    @controller.stubs(:current_resource).returns(stub(id: 123))

    result = @controller.send(:build_chart_ransack_params, {})

    assert_equal 123, result[:summarizable_id_eq]
  end

  test "build_chart_ransack_params returns base params for index action" do
    @controller.stubs(:show_action?).returns(false)

    result = @controller.send(:build_chart_ransack_params, { test: "value" })

    assert_includes result.keys, :test
    refute_includes result.keys, :summarizable_id_eq
  end

  # build_table_ransack_params Tests

  test "build_table_ransack_params calls build_show_table_ransack_params for show" do
    @controller.stubs(:show_action?).returns(true)
    @controller.expects(:build_show_table_ransack_params).with({ test: "value" }).returns({})

    @controller.send(:build_table_ransack_params, { test: "value" })
  end

  test "build_table_ransack_params calls build_index_table_ransack_params for index" do
    @controller.stubs(:show_action?).returns(false)
    @controller.expects(:build_index_table_ransack_params).with({ test: "value" }).returns({})

    @controller.send(:build_table_ransack_params, { test: "value" })
  end

  # build_show_table_ransack_params Tests

  test "build_show_table_ransack_params adds occurred_at filters when times present" do
    @controller.instance_variable_set(:@table_start_time, 5.days.ago.to_i)
    @controller.instance_variable_set(:@table_end_time, Time.current.to_i)

    result = @controller.send(:build_show_table_ransack_params, {})

    assert_includes result.keys, :occurred_at_gteq
    assert_includes result.keys, :occurred_at_lt
    assert_kind_of Time, result[:occurred_at_gteq]
    assert_kind_of Time, result[:occurred_at_lt]
  end

  test "build_show_table_ransack_params skips time filters when times nil" do
    @controller.instance_variable_set(:@table_start_time, nil)
    @controller.instance_variable_set(:@table_end_time, nil)

    result = @controller.send(:build_show_table_ransack_params, {})

    refute_includes result.keys, :occurred_at_gteq
    refute_includes result.keys, :occurred_at_lt
  end

  test "build_show_table_ransack_params merges show_resource_filter" do
    @controller.stubs(:show_resource_filter).returns({ route_id_eq: 456 })

    result = @controller.send(:build_show_table_ransack_params, {})

    assert_equal 456, result[:route_id_eq]
  end

  test "build_show_table_ransack_params adds duration_gteq when threshold > 0" do
    @controller.instance_variable_set(:@start_duration, 300)

    result = @controller.send(:build_show_table_ransack_params, {})

    assert_equal 300, result[:duration_gteq]
  end

  # build_index_table_ransack_params Tests

  test "build_index_table_ransack_params adds period_start filters when times present" do
    @controller.instance_variable_set(:@table_start_time, 7.days.ago.to_i)
    @controller.instance_variable_set(:@table_end_time, Time.current.to_i)

    result = @controller.send(:build_index_table_ransack_params, {})

    assert_includes result.keys, :period_start_gteq
    assert_includes result.keys, :period_start_lt
    assert_kind_of Time, result[:period_start_gteq]
    assert_kind_of Time, result[:period_start_lt]
  end

  test "build_index_table_ransack_params skips time filters when times nil" do
    @controller.instance_variable_set(:@table_start_time, nil)
    @controller.instance_variable_set(:@table_end_time, nil)

    result = @controller.send(:build_index_table_ransack_params, {})

    refute_includes result.keys, :period_start_gteq
    refute_includes result.keys, :period_start_lt
  end

  test "build_index_table_ransack_params adds summarizable_type when present" do
    @controller.stubs(:summarizable_type).returns("RailsPulse::Job")

    result = @controller.send(:build_index_table_ransack_params, {})

    assert_equal "RailsPulse::Job", result[:summarizable_type_eq]
  end

  test "build_index_table_ransack_params adds avg_duration_gteq when threshold > 0" do
    @controller.instance_variable_set(:@start_duration, 1000)

    result = @controller.send(:build_index_table_ransack_params, {})

    assert_equal 1000, result[:avg_duration_gteq]
  end

  # Helper Method Tests

  test "show_action? returns true when action_name is show" do
    @controller.stubs(:action_name).returns("show")

    assert @controller.send(:show_action?)
  end

  test "show_action? returns false when action_name is not show" do
    @controller.stubs(:action_name).returns("index")

    refute @controller.send(:show_action?)
  end

  test "handle_pagination calls set_pagination_limit when limit param present" do
    @controller.params = ActionController::Parameters.new({ limit: 25 })
    @controller.expects(:set_pagination_limit).with(25)

    @controller.send(:handle_pagination)
  end

  test "handle_pagination does nothing when limit param not present" do
    @controller.params = ActionController::Parameters.new({})
    @controller.expects(:set_pagination_limit).never

    @controller.send(:handle_pagination)
  end

  test "setup_zoom_range_data calls setup_zoom_range with times" do
    @controller.instance_variable_set(:@start_time, 7.days.ago.to_i)
    @controller.instance_variable_set(:@end_time, Time.current.to_i)
    @controller.expects(:setup_zoom_range).with(7.days.ago.to_i, Time.current.to_i).returns([ nil, nil, 7.days.ago.to_i, Time.current.to_i ])

    @controller.send(:setup_zoom_range_data)
  end

  test "setup_time_and_response_ranges calls setup_time_range and setup_duration_range" do
    @controller.expects(:setup_time_range).returns([ 1.day.ago.to_i, Time.current.to_i, "last_24_hours", 24.0 ])
    @controller.expects(:setup_duration_range).returns([ 0, :all ])

    @controller.send(:setup_time_and_response_ranges)

    assert @controller.instance_variable_defined?(:@start_time)
    assert @controller.instance_variable_defined?(:@end_time)
    assert @controller.instance_variable_defined?(:@selected_time_range)
    assert @controller.instance_variable_defined?(:@time_diff_hours)
    assert @controller.instance_variable_defined?(:@start_duration)
    assert @controller.instance_variable_defined?(:@selected_response_range)
  end
end
