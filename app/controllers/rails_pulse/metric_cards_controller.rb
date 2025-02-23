module RailsPulse
  class MetricCardsController < ApplicationController
    include TimeRangeConcern
    include ResponseRangeConcern

    before_action :setup_time_and_response_ranges
    before_action :set_metric_type
    before_action :set_context
    before_action :set_cache_key

    def show
      if RailsPulse.configuration.metric_cache_enabled
        @metric_data = Rails.cache.fetch(@cache_key, expires_in: RailsPulse.configuration.metric_cache_duration) do
          calculate_metric_data
        end
      else
        @metric_data = calculate_metric_data
      end

      respond_to do |format|
        format.html
      end
    end

    private

    def set_metric_type
      @metric_type = params[:id]
    end

    def set_context
      @context = params[:context] || "routes"
    end

    def set_cache_key
      @cache_key = [
        "rails_pulse_metric",
        @context,
        @metric_type,
        cache_period_key,
        current_filters_digest
      ]
    end

    def cache_period_key
      # Creates a key that changes every cache duration period with jitter per metric
      cache_duration = RailsPulse.configuration.metric_cache_duration.to_i
      # Add metric-specific offset to stagger cache expirations (up to 25% of cache duration)
      max_jitter = (cache_duration * 0.25).to_i
      metric_offset = Digest::MD5.hexdigest(@metric_type).hex % max_jitter
      adjusted_time = Time.current.to_i + metric_offset
      (adjusted_time / cache_duration)
    end

    def current_filters_digest
      # Include current filters in cache key
      filter_params = params.slice(:q, :time_range, :duration).permit!.to_h
      Digest::MD5.hexdigest(filter_params.to_s)
    end

    def calculate_metric_data
      route = extract_route_from_context
      
      case @metric_type
      when "average_response_times"
        Routes::Cards::AverageResponseTimes.new(route: route).to_metric_card
      when "percentile_response_times"
        Routes::Cards::PercentileResponseTimes.new(route: route).to_metric_card
      when "request_count_totals"
        Routes::Cards::RequestCountTotals.new(route: route).to_metric_card
      when "error_rate_per_route"
        Routes::Cards::ErrorRatePerRoute.new(route: route).to_metric_card
      else
        { title: "Unknown Metric", summary: "N/A" }
      end
    end

    def extract_route_from_context
      # Extract route ID from context like "route_123" or return nil for "routes"/"requests"
      if @context.match(/^route_(\d+)$/)
        route_id = @context.match(/^route_(\d+)$/)[1]
        Route.find(route_id)
      else
        nil
      end
    end

    def setup_time_and_response_ranges
      @start_time, @end_time, @selected_time_range, @time_diff_hours = setup_time_range
      @start_duration, @selected_response_range = setup_duration_range
    end
  end
end
