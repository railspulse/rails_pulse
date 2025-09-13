module ZoomRangeConcern
  extend ActiveSupport::Concern

  def setup_zoom_range(main_start_time, main_end_time)
    # Extract column selection parameter (but don't delete it yet - we need it for the view)
    selected_column_time = params[:selected_column_time]

    # Extract zoom parameters from params (this removes them from params)
    zoom_start = params.delete(:zoom_start_time)
    zoom_end = params.delete(:zoom_end_time)

    # Handle column selection with highest precedence for table filtering
    if selected_column_time
      column_start, column_end = normalize_column_time(selected_column_time.to_i, main_start_time, main_end_time)
      table_start_time = column_start
      table_end_time = column_end
      # Don't set zoom times for column selection - let chart show full range
      return [ zoom_start, zoom_end, table_start_time, table_end_time ]
    end

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

  def normalize_column_time(column_time, main_start_time, main_end_time)
    # Determine period type based on main time range (same logic as ChartTableConcern)
    time_diff_hours = (main_end_time - main_start_time) / 3600.0

    if time_diff_hours <= 25
      # Hourly period - normalize to beginning/end of hour
      column_time_obj = Time.zone&.at(column_time) || Time.at(column_time)
      start_time = column_time_obj&.beginning_of_hour || column_time_obj
      end_time = column_time_obj&.end_of_hour || column_time_obj
    else
      # Daily period - normalize to beginning/end of day
      column_time_obj = Time.zone&.at(column_time) || Time.at(column_time)
      start_time = column_time_obj&.beginning_of_day || column_time_obj
      end_time = column_time_obj&.end_of_day || column_time_obj
    end

    [ start_time.to_i, end_time.to_i ]
  end

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
