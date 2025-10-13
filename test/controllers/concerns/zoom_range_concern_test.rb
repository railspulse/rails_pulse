require "test_helper"

class ZoomRangeConcernTest < ActionController::TestCase
  class TestController < ActionController::Base
    include ZoomRangeConcern
  end

  # TODO: Test setup_zoom_range with no parameters returns main times for table
  # TODO: Test setup_zoom_range with zoom_start and zoom_end normalizes and returns zoom times
  # TODO: Test setup_zoom_range with selected_column_time takes precedence over zoom
  # TODO: Test setup_zoom_range removes zoom parameters from params
  # TODO: Test setup_zoom_range keeps selected_column_time in params for view
  # TODO: Test normalize_column_time returns beginning/end of hour for hourly periods
  # TODO: Test normalize_column_time returns beginning/end of day for daily periods
  # TODO: Test normalize_zoom_times normalizes to hour boundaries for ranges <=25 hours
  # TODO: Test normalize_zoom_times normalizes to day boundaries for ranges >25 hours
  # TODO: Test that zoom times are returned as integers (Unix timestamps)
end
