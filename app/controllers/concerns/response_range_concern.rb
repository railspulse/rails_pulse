module ResponseRangeConcern
  extend ActiveSupport::Concern

  def setup_duration_range(type = :route)
    ransack_params = params[:q] || {}
    thresholds = RailsPulse.configuration.public_send("#{type}_thresholds")

    # Check all duration-related parameters
    # avg_duration for Summary, duration for Request/Operation, duration_gteq for direct Ransack filtering
    duration_param = ransack_params[:avg_duration] || ransack_params[:duration] || ransack_params[:duration_gteq]

    # Priority 1: Page-specific duration filter
    if duration_param.present?
      selected_range = duration_param
      start_duration =
        case duration_param.to_sym
        when :slow then thresholds[:slow]
        when :very_slow then thresholds[:very_slow]
        when :critical then thresholds[:critical]
        else 0
        end
    # Priority 2: Global performance threshold filter
    elsif (global_threshold = session_global_filters["performance_threshold"]).present?
      selected_range = global_threshold.to_sym
      start_duration =
        case global_threshold.to_sym
        when :slow then thresholds[:slow]
        when :very_slow then thresholds[:very_slow]
        when :critical then thresholds[:critical]
        else 0
        end
    # Priority 3: No filter (show all)
    else
      start_duration = 0
      selected_range = :all
    end

    [ start_duration, selected_range ]
  end
end
