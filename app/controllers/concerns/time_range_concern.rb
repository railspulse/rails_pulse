module TimeRangeConcern
  extend ActiveSupport::Concern

  included do
    # Define the constant in the including class - ordered by most common usage
    const_set(:TIME_RANGE_OPTIONS, [
      [ "Last 24 hours", :last_day ],
      [ "Last Week", :last_week ],
      [ "Last Month", :last_month ],
      [ "Custom Range...", :custom ]
    ].freeze)
  end

  def setup_time_range
    start_time = 1.day.ago
    end_time = Time.zone.now
    selected_time_range = :last_day

    ransack_params = params[:q] || {}

    # Priority 1: Page-specific preset from dropdown (check this first!)
    if ransack_params[:period_start_range].present? && ransack_params[:period_start_range].to_sym != :custom
      # Predefined time range from dropdown
      selected_time_range = ransack_params[:period_start_range]
      start_time =
        case selected_time_range.to_sym
        when :last_day then 1.day.ago
        when :last_week then 1.week.ago
        when :last_month then 1.month.ago
        else 1.day.ago # Default fallback
        end
    # Priority 2: Page-specific custom datetime range from picker (only if period_start_range is :custom)
    elsif ransack_params[:period_start_range].present? && ransack_params[:period_start_range].to_sym == :custom && ransack_params[:custom_date_range].present? && ransack_params[:custom_date_range].include?(" to ")
      # Custom datetime range from custom range picker
      dates = ransack_params[:custom_date_range].split(" to ")
      start_time = parse_time_param(dates[0].strip)
      end_time = parse_time_param(dates[1].strip)
      selected_time_range = :custom
    # Priority 3: Page-specific filters (chart zoom)
    elsif ransack_params[:occurred_at_gteq].present? && ransack_params[:occurred_at_lt].present?
      # Custom time range from chart zoom
      start_time = parse_time_param(ransack_params[:occurred_at_gteq])
      end_time = parse_time_param(ransack_params[:occurred_at_lt])
      selected_time_range = :custom
    # Priority 4: Global filters (from session)
    elsif session_global_filters["start_time"].present? || session_global_filters["end_time"].present?
      start_time = parse_time_param(session_global_filters["start_time"]) if session_global_filters["start_time"].present?
      end_time = parse_time_param(session_global_filters["end_time"]) if session_global_filters["end_time"].present?
      selected_time_range = :custom
    end
    # Priority 5: Default time range (already set above)

    time_diff = (end_time.to_i - start_time.to_i) / 3600.0

    if time_diff <= 25
      start_time = start_time.beginning_of_hour
      end_time = end_time.end_of_hour
    else
      start_time = start_time.beginning_of_day
      end_time = end_time.end_of_day
    end

    [ start_time.to_i, end_time.to_i, selected_time_range, time_diff ]
  end

  private

  def parse_time_param(param)
    case param
    when Time, DateTime
      param.in_time_zone
    when String
      # Parse as server local time (not UTC, not Time.zone)
      # This ensures flatpickr datetime strings are interpreted in server's timezone
      Time.parse(param).localtime
    else
      # Assume it's an integer timestamp
      Time.zone.at(param.to_i)
    end
  end
end
