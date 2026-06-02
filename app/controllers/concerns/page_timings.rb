# frozen_string_literal: true

PageTimings = Struct.new(
  :start_time, :end_time,
  :table_start_time, :table_end_time,
  :zoom_start, :zoom_end,
  :time_diff_hours, :start_duration,
  :selected_time_range, :selected_response_range,
  keyword_init: true
)
