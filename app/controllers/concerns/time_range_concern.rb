module TimeRangeConcern
  extend ActiveSupport::Concern

  included do
    # Define the constant in the including class
    const_set(:TIME_RANGE_OPTIONS, [
      [ "Last 24 hours", :last_day ],
      [ "Last Week", :last_week ],
      [ "Last Month", :last_month ],
      [ "All Time", :all_time ]
    ].freeze)
  end

  def setup_time_range
    start_time = 0
    end_time = Time.zone.now.to_i
    selected_time_range = :all_time

    ransack_params = params[:q] || {}

    if ransack_params[:requests_occurred_at_gteq].present?
      # Custom time range from routes index chart zoom which filters requests through an association
      start_time = ransack_params[:requests_occurred_at_gteq].to_i
      end_time = ransack_params[:requests_occurred_at_lt].to_i
    elsif ransack_params[:occurred_at_gteq].present?
      # Custom time range from chart zoom where there is no association
      start_time = ransack_params[:occurred_at_gteq].to_i
      end_time = ransack_params[:occurred_at_lt].to_i
    elsif ransack_params[:occurred_at_range]
      # Predefined time range from dropdown
      selected_time_range = ransack_params[:occurred_at_range]
      start_time =
        case selected_time_range.to_sym
        when :last_day then 1.day.ago.to_i
        when :last_week then 1.week.ago.to_i
        when :last_month then 1.month.ago.to_i
        when :all_time then 0
        end
    end

    time_diff = (end_time - start_time) / 3600.0

    if time_diff <= 25
      start_time = Time.zone.at(start_time).beginning_of_hour.to_i
      end_time = Time.zone.at(end_time).end_of_hour.to_i
    else
      start_time = Time.zone.at(start_time).beginning_of_day.to_i
      end_time = Time.zone.at(end_time).end_of_day.to_i
    end

    [ start_time, end_time, selected_time_range, time_diff ]
  end
end
