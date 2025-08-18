module ZoomRangeConcern
  extend ActiveSupport::Concern

  def setup_zoom_range(main_start_time, main_end_time)
    # Extract zoom parameters from params (this removes them from params)
    zoom_start = params.delete(:zoom_start_time)
    zoom_end = params.delete(:zoom_end_time)

    # Normalize zoom times to beginning/end of day or hour like we do for main time range
    if zoom_start && zoom_end
      zoom_start, zoom_end = normalize_zoom_times(zoom_start.to_i, zoom_end.to_i)
    end

    # Calculate table times - use zoom if present, otherwise fallback to main times
    table_start_time = zoom_start || main_start_time
    table_end_time = zoom_end || main_end_time

    [ zoom_start, zoom_end, table_start_time, table_end_time ]
  end

  private

  def normalize_zoom_times(start_time, end_time)
    time_diff = (end_time - start_time) / 3600.0

    if time_diff <= 25
      start_time_obj = Time.zone&.at(start_time) || Time.at(start_time)
      end_time_obj = Time.zone&.at(end_time) || Time.at(end_time)
      start_time = start_time_obj&.beginning_of_hour || start_time_obj
      end_time = end_time_obj&.end_of_hour || end_time_obj
    else
      start_time_obj = Time.zone&.at(start_time) || Time.at(start_time)
      end_time_obj = Time.zone&.at(end_time) || Time.at(end_time)
      start_time = start_time_obj&.beginning_of_day || start_time_obj
      end_time = end_time_obj&.end_of_day || end_time_obj
    end

    [ start_time.to_i, end_time.to_i ]
  end
end
