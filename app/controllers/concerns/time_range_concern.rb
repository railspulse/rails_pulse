module TimeRangeConcern
  extend ActiveSupport::Concern

  included do
    # Define the constant in the including class - ordered by most common usage
    const_set(:TIME_RANGE_OPTIONS, [
      [ "Last 24 hours", :last_day ],
      [ "Last Week", :last_week ],
      [ "Last Month", :last_month ]
    ].freeze)
  end

  def setup_time_range
    start_time = 1.day.ago
    end_time = Time.zone.now
    selected_time_range = :last_day

    ransack_params = params[:q] || {}

    if ransack_params[:occurred_at_gteq].present?
      # Custom time range from chart zoom where there is no association
      start_time = parse_time_param(ransack_params[:occurred_at_gteq])
      end_time = parse_time_param(ransack_params[:occurred_at_lt])
    elsif ransack_params[:period_start_range]
      # Predefined time range from dropdown
      selected_time_range = ransack_params[:period_start_range]
      start_time =
        case selected_time_range.to_sym
        when :last_day then 1.day.ago
        when :last_week then 1.week.ago
        when :last_month then 1.month.ago
        else 1.day.ago # Default fallback
        end
    end

    time_diff = (end_time.to_i - start_time.to_i) / 3600.0

    if time_diff <= 25
      start_time = start_time.beginning_of_hour
      end_time = end_time.end_of_hour
    else
      start_time = start_time.beginning_of_day
      end_time = end_time.end_of_day
    end

    [ start_time, end_time, selected_time_range, time_diff ]
  end

  private

  def parse_time_param(param)
    case param
    when Time, DateTime
      param.in_time_zone
    when String
      Time.zone.parse(param)
    else
      # Assume it's an integer timestamp
      Time.zone.at(param.to_i)
    end
  end
end
