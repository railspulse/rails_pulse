require "test_helper"

class ZoomRangeConcernTest < ActionController::TestCase
  class TestController < ActionController::Base
    include ZoomRangeConcern

    attr_accessor :params

    def initialize
      super
      @params = ActionController::Parameters.new({})
    end
  end

  setup do
    @controller = TestController.new
    @now = Time.current
    travel_to @now
  end

  teardown do
    travel_back
  end

  # Structure Tests

  test "setup_zoom_range returns array with 4 elements" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i

    result = @controller.send(:setup_zoom_range, main_start, main_end)

    assert_kind_of Array, result
    assert_equal 4, result.length
  end

  test "setup_zoom_range returns integer timestamps" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i

    zoom_start, zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # zoom_start and zoom_end can be nil
    assert(zoom_start.nil? || zoom_start.is_a?(Integer))
    assert(zoom_end.nil? || zoom_end.is_a?(Integer))
    assert_kind_of Integer, table_start
    assert_kind_of Integer, table_end
  end

  # Column Selection Tests

  test "setup_zoom_range uses selected_column_time with highest precedence" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i
    column_time_ms = 3.days.ago.to_i * 1000  # In milliseconds

    @controller.params[:selected_column_time] = column_time_ms
    @controller.params[:zoom_start_time] = 5.days.ago.to_i * 1000
    @controller.params[:zoom_end_time] = 4.days.ago.to_i * 1000

    zoom_start, zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Column selection has highest precedence - zoom params are extracted but not used
    # The returned zoom values are the raw extracted params (in milliseconds)
    assert_kind_of Integer, zoom_start  # Raw milliseconds from params.delete
    assert_kind_of Integer, zoom_end

    # Table times should be set based on column (normalized seconds)
    assert_kind_of Integer, table_start
    assert_kind_of Integer, table_end
    # Table times should be different from zoom times (table is normalized, zoom is raw)
    refute_equal zoom_start, table_start
  end

  test "setup_zoom_range keeps selected_column_time in params" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i
    column_time_ms = 3.days.ago.to_i * 1000

    @controller.params[:selected_column_time] = column_time_ms

    @controller.send(:setup_zoom_range, main_start, main_end)

    # selected_column_time should NOT be deleted from params
    assert @controller.params.key?(:selected_column_time)
  end

  test "setup_zoom_range divides column_time by 1000 for milliseconds" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i
    column_time_seconds = 3.days.ago.to_i
    column_time_ms = column_time_seconds * 1000

    @controller.params[:selected_column_time] = column_time_ms

    _zoom_start, _zoom_end, table_start, _table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Table start should be around the column time (within a day for normalization)
    assert_in_delta column_time_seconds, table_start, 86400
  end

  test "setup_zoom_range normalizes column to hour for <= 25 hour range" do
    main_start = 20.hours.ago.to_i
    main_end = @now.to_i
    column_time_ms = 10.hours.ago.to_i * 1000

    @controller.params[:selected_column_time] = column_time_ms

    _zoom_start, _zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Should be normalized to hour boundaries
    start_obj = Time.zone.at(table_start)
    end_obj = Time.zone.at(table_end)

    assert_equal 0, start_obj.min
    assert_equal 0, start_obj.sec
    assert_equal 59, end_obj.min
    assert_equal 59, end_obj.sec
  end

  test "setup_zoom_range normalizes column to day for > 25 hour range" do
    main_start = 30.days.ago.to_i
    main_end = @now.to_i
    column_time_ms = 15.days.ago.to_i * 1000

    @controller.params[:selected_column_time] = column_time_ms

    _zoom_start, _zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Should be normalized to day boundaries
    assert_equal 0, Time.zone.at(table_start).hour
    assert_equal 23, Time.zone.at(table_end).hour
  end

  # Zoom Parameter Tests

  test "setup_zoom_range uses zoom_start and zoom_end" do
    main_start = 30.days.ago.to_i
    main_end = @now.to_i
    zoom_start_ms = 10.days.ago.to_i * 1000
    zoom_end_ms = 5.days.ago.to_i * 1000

    @controller.params[:zoom_start_time] = zoom_start_ms
    @controller.params[:zoom_end_time] = zoom_end_ms

    zoom_start, zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    assert_kind_of Integer, zoom_start
    assert_kind_of Integer, zoom_end
    assert_equal zoom_start, table_start
    assert_equal zoom_end, table_end
  end

  test "setup_zoom_range deletes zoom params from params hash" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i
    zoom_start_ms = 5.days.ago.to_i * 1000
    zoom_end_ms = 3.days.ago.to_i * 1000

    @controller.params[:zoom_start_time] = zoom_start_ms
    @controller.params[:zoom_end_time] = zoom_end_ms

    @controller.send(:setup_zoom_range, main_start, main_end)

    # Zoom params should be deleted
    refute @controller.params.key?(:zoom_start_time)
    refute @controller.params.key?(:zoom_end_time)
  end

  test "setup_zoom_range normalizes zoom times" do
    main_start = 30.days.ago.to_i
    main_end = @now.to_i
    zoom_start_ms = 10.days.ago.to_i * 1000
    zoom_end_ms = 8.days.ago.to_i * 1000

    @controller.params[:zoom_start_time] = zoom_start_ms
    @controller.params[:zoom_end_time] = zoom_end_ms

    zoom_start, zoom_end, _table_start, _table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Should be normalized to day boundaries (> 25 hours)
    assert_equal 0, Time.zone.at(zoom_start).hour
    assert_equal 23, Time.zone.at(zoom_end).hour
  end

  test "setup_zoom_range converts zoom milliseconds to seconds" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i
    zoom_start_seconds = 5.days.ago.to_i
    zoom_start_ms = zoom_start_seconds * 1000
    zoom_end_seconds = 3.days.ago.to_i
    zoom_end_ms = zoom_end_seconds * 1000

    @controller.params[:zoom_start_time] = zoom_start_ms
    @controller.params[:zoom_end_time] = zoom_end_ms

    zoom_start, zoom_end, _table_start, _table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Zoom times should be in seconds and normalized
    assert_in_delta zoom_start_seconds, zoom_start, 86400  # Within a day for normalization
    assert_in_delta zoom_end_seconds, zoom_end, 86400
  end

  test "setup_zoom_range returns zoom times for table filtering" do
    main_start = 30.days.ago.to_i
    main_end = @now.to_i
    zoom_start_ms = 10.days.ago.to_i * 1000
    zoom_end_ms = 5.days.ago.to_i * 1000

    @controller.params[:zoom_start_time] = zoom_start_ms
    @controller.params[:zoom_end_time] = zoom_end_ms

    zoom_start, zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Table should use zoom times
    assert_equal zoom_start, table_start
    assert_equal zoom_end, table_end
  end

  test "setup_zoom_range does not delete selected_column_time from params" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i
    column_time_ms = 3.days.ago.to_i * 1000

    @controller.params[:selected_column_time] = column_time_ms
    @controller.params[:zoom_start_time] = 5.days.ago.to_i * 1000
    @controller.params[:zoom_end_time] = 4.days.ago.to_i * 1000

    @controller.send(:setup_zoom_range, main_start, main_end)

    # Column time should remain in params for view
    assert @controller.params.key?(:selected_column_time)

    # But zoom times should be deleted
    refute @controller.params.key?(:zoom_start_time)
    refute @controller.params.key?(:zoom_end_time)
  end

  # Fallback Tests

  test "setup_zoom_range returns main times when no zoom or column" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i

    zoom_start, zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    assert_nil zoom_start
    assert_nil zoom_end
    assert_equal main_start, table_start
    assert_equal main_end, table_end
  end

  test "setup_zoom_range uses main_start_time for table_start_time when no zoom" do
    main_start = 14.days.ago.to_i
    main_end = @now.to_i

    _zoom_start, _zoom_end, table_start, _table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    assert_equal main_start, table_start
  end

  # Normalization Tests

  test "normalize_column_time returns hour boundaries for hourly period" do
    main_start = 10.hours.ago.to_i
    main_end = @now.to_i
    column_time_ms = 5.hours.ago.to_i * 1000

    @controller.params[:selected_column_time] = column_time_ms

    _zoom_start, _zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Check hour boundaries
    start_obj = Time.zone.at(table_start)
    end_obj = Time.zone.at(table_end)

    assert_equal 0, start_obj.min
    assert_equal 0, start_obj.sec
    assert_equal 59, end_obj.min
    assert_equal 59, end_obj.sec
  end

  test "normalize_column_time returns day boundaries for daily period" do
    main_start = 60.days.ago.to_i
    main_end = @now.to_i
    column_time_ms = 30.days.ago.to_i * 1000

    @controller.params[:selected_column_time] = column_time_ms

    _zoom_start, _zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Check day boundaries
    start_obj = Time.zone.at(table_start)
    end_obj = Time.zone.at(table_end)

    assert_equal 0, start_obj.hour
    assert_equal 23, end_obj.hour
  end

  test "normalize_zoom_times normalizes to hour boundaries for <= 25 hours" do
    main_start = 30.days.ago.to_i
    main_end = @now.to_i
    zoom_start_ms = 20.hours.ago.to_i * 1000
    zoom_end_ms = 5.hours.ago.to_i * 1000

    @controller.params[:zoom_start_time] = zoom_start_ms
    @controller.params[:zoom_end_time] = zoom_end_ms

    zoom_start, zoom_end, _table_start, _table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Zoom diff is ~15 hours, should use hour boundaries
    start_obj = Time.zone.at(zoom_start)
    end_obj = Time.zone.at(zoom_end)

    assert_equal 0, start_obj.min
    assert_equal 0, start_obj.sec
    assert_equal 59, end_obj.min
    assert_equal 59, end_obj.sec
  end

  test "normalize_zoom_times normalizes to day boundaries for > 25 hours" do
    main_start = 30.days.ago.to_i
    main_end = @now.to_i
    zoom_start_ms = 10.days.ago.to_i * 1000
    zoom_end_ms = 5.days.ago.to_i * 1000

    @controller.params[:zoom_start_time] = zoom_start_ms
    @controller.params[:zoom_end_time] = zoom_end_ms

    zoom_start, zoom_end, _table_start, _table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Zoom diff is ~5 days, should use day boundaries
    start_obj = Time.zone.at(zoom_start)
    end_obj = Time.zone.at(zoom_end)

    assert_equal 0, start_obj.hour
    assert_equal 23, end_obj.hour
  end

  test "normalize methods use Time.zone when available" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i
    column_time_ms = 3.days.ago.to_i * 1000

    # Time.zone should be available in test environment
    assert_not_nil Time.zone

    @controller.params[:selected_column_time] = column_time_ms

    _zoom_start, _zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Should successfully return normalized times using Time.zone
    assert_kind_of Integer, table_start
    assert_kind_of Integer, table_end
  end

  test "normalize methods handle conversion properly" do
    main_start = 30.days.ago.to_i
    main_end = @now.to_i
    zoom_start_ms = 10.days.ago.to_i * 1000
    zoom_end_ms = 8.days.ago.to_i * 1000

    @controller.params[:zoom_start_time] = zoom_start_ms
    @controller.params[:zoom_end_time] = zoom_end_ms

    zoom_start, zoom_end, _table_start, _table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Both should be valid Unix timestamps (seconds since epoch)
    assert_operator zoom_start, :>, 1_600_000_000  # After Sept 2020
    assert_operator zoom_end, :>, 1_600_000_000
    assert_operator zoom_end, :>, zoom_start
  end

  # Edge Cases

  test "setup_zoom_range handles nil zoom parameters gracefully" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i

    # Don't set zoom params
    zoom_start, zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # Should return nil for zoom and main times for table
    assert_nil zoom_start
    assert_nil zoom_end
    assert_equal main_start, table_start
    assert_equal main_end, table_end
  end

  test "setup_zoom_range handles only zoom_start present" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i
    zoom_start_ms = 5.days.ago.to_i * 1000
    @controller.params[:zoom_start_time] = zoom_start_ms

    # Only start, no end
    zoom_start, zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # params.delete() extracts the value (returns the raw millisecond value)
    assert_equal zoom_start_ms, zoom_start  # Raw milliseconds returned
    assert_nil zoom_end  # This one wasn't set

    # Table uses zoom_start (raw milliseconds) since it's present, and main_end for the missing one
    assert_equal zoom_start_ms, table_start  # Uses raw zoom value
    assert_equal main_end, table_end  # Falls back to main for missing zoom_end
  end

  test "setup_zoom_range handles only zoom_end present" do
    main_start = 7.days.ago.to_i
    main_end = @now.to_i
    zoom_end_ms = 3.days.ago.to_i * 1000
    @controller.params[:zoom_end_time] = zoom_end_ms

    # Only end, no start
    zoom_start, zoom_end, table_start, table_end = @controller.send(:setup_zoom_range, main_start, main_end)

    # params.delete() extracts the value (returns the raw millisecond value)
    assert_nil zoom_start  # This one wasn't set
    assert_equal zoom_end_ms, zoom_end  # Raw milliseconds returned

    # Table uses main_start for missing zoom_start, and zoom_end (raw milliseconds) since it's present
    assert_equal main_start, table_start  # Falls back to main for missing zoom_start
    assert_equal zoom_end_ms, table_end  # Uses raw zoom value
  end
end
