module ResponseRangeConcern
  extend ActiveSupport::Concern

  def setup_duration_range(type = :route)
    ransack_params = params[:q] || {}
    thresholds = RailsPulse.configuration.public_send("#{type}_thresholds")

    # Check both avg_duration (for Summary) and duration (for Request/Operation)
    duration_param = ransack_params[:avg_duration] || ransack_params[:duration]

    if duration_param.present?
      selected_range = duration_param
      start_duration =
        case duration_param.to_sym
        when :slow then thresholds[:slow]
        when :very_slow then thresholds[:very_slow]
        when :critical then thresholds[:critical]
        else 0
        end
    else
      start_duration = 0
      selected_range = :all
    end

    [ start_duration, selected_range ]
  end
end
