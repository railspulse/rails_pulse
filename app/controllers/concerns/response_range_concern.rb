module ResponseRangeConcern
  extend ActiveSupport::Concern

  def setup_duration_range(type = :route)
    ransack_params = params[:q] || {}
    thresholds = RailsPulse.configuration.public_send("#{type}_thresholds")

    if ransack_params[:duration].present?
      selected_range = ransack_params[:duration]
      start_duration =
        case ransack_params[:duration].to_sym
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
