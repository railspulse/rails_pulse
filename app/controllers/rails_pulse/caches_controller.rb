module RailsPulse
  class CachesController < ApplicationController
    def show
      @component_id = params[:id]
      @context = params[:context]
      @cache_key = ComponentCacheKey.build(@component_id, @context)

      # Preserve component options before refresh
      existing_options = {}
      if params[:refresh]
        existing_cache = Rails.cache.read(@cache_key)
        existing_options = existing_cache[:component_options] if existing_cache&.dig(:component_options)
        Rails.cache.delete(@cache_key)
      end

      # Check if cache exists with just options (from render_skeleton_with_frame)
      cached_data = Rails.cache.read(@cache_key)
      if cached_data && !cached_data[:component_data]
        # Merge options with full data
        cached_data = {
          component_data: calculate_component_data,
          cached_at: Time.current,
          component_options: cached_data[:component_options] || {}
        }
        Rails.cache.write(@cache_key, cached_data, expires_in: ComponentCacheKey.cache_expires_in)
      elsif !cached_data
        # No cache exists, create new one (use preserved options if refreshing)
        cached_data = {
          component_data: calculate_component_data,
          cached_at: Time.current,
          component_options: existing_options
        }
        Rails.cache.write(@cache_key, cached_data, expires_in: ComponentCacheKey.cache_expires_in)
      end

      @component_data = cached_data[:component_data]
      @cached_at = cached_data[:cached_at]
      @component_options = cached_data[:component_options] || {}

      # Update cached_at timestamp in component options if refresh action exists
      if params[:refresh] && @component_options[:actions]
        update_cached_at_in_actions(@component_options[:actions], @cached_at)
        # Update the unified cache with new cached_at timestamp
        cached_data[:component_options] = @component_options
        Rails.cache.write(@cache_key, cached_data, expires_in: ComponentCacheKey.cache_expires_in)
      end
    end

    private

    def calculate_component_data
      route = extract_route_from_context
      query = extract_query_from_context

      case [@context, @component_id]
      # Routes context
      when ["routes", "average_response_times"], [/^route_\d+$/, "average_response_times"]
        Routes::Cards::AverageResponseTimes.new(route: route).to_metric_card
      when ["routes", "percentile_response_times"], [/^route_\d+$/, "percentile_response_times"]
        Routes::Cards::PercentileResponseTimes.new(route: route).to_metric_card
      when ["routes", "request_count_totals"], [/^route_\d+$/, "request_count_totals"]
        Routes::Cards::RequestCountTotals.new(route: route).to_metric_card
      when ["routes", "error_rate_per_route"], [/^route_\d+$/, "error_rate_per_route"]
        Routes::Cards::ErrorRatePerRoute.new(route: route).to_metric_card
      
      # Requests context
      when ["requests", "average_response_times"]
        Requests::Cards::AverageResponseTimes.new.to_metric_card
      when ["requests", "percentile_response_times"]
        Requests::Cards::PercentileResponseTimes.new.to_metric_card
      when ["requests", "request_count_totals"]
        Requests::Cards::RequestCountTotals.new.to_metric_card
      when ["requests", "error_rate_per_route"]
        Requests::Cards::ErrorRatePerRoute.new.to_metric_card
      
      # Queries context
      when ["queries", "average_query_times"], [/^query_\d+$/, "average_query_times"]
        Queries::Cards::AverageQueryTimes.new(query: query).to_metric_card
      when ["queries", "percentile_query_times"], [/^query_\d+$/, "percentile_query_times"]
        Queries::Cards::PercentileQueryTimes.new(query: query).to_metric_card
      when ["queries", "execution_rate"], [/^query_\d+$/, "execution_rate"]
        Queries::Cards::ExecutionRate.new(query: query).to_metric_card
      when ["queries", "query_count_totals"], [/^query_\d+$/, "query_count_totals"]
        Queries::Cards::QueryCountTotals.new(query: query).to_metric_card
      
      # Dashboard context
      when [nil, "dashboard_average_response_time"]
        Dashboard::Charts::AverageResponseTime.new.to_chart_data
      when [nil, "dashboard_p95_response_time"]
        Dashboard::Charts::P95ResponseTime.new.to_chart_data
      when [nil, "dashboard_slow_routes"]
        Dashboard::Tables::SlowRoutes.new.to_table_data
      when [nil, "dashboard_slow_queries"]
        Dashboard::Tables::SlowQueries.new.to_table_data
      else
        { title: "Unknown Metric", summary: "N/A" }
      end
    end

    def extract_route_from_context
      return unless @context

      # Extract route ID from context like "route_123" or return nil for "routes"/"requests"
      if @context.match(/^route_(\d+)$/)
        route_id = @context.match(/^route_(\d+)$/)[1]
        Route.find(route_id)
      else
        nil
      end
    end

    def extract_query_from_context
      return unless @context

      # Extract query ID from context like "query_123" or return nil for other contexts
      if @context.match(/^query_(\d+)$/)
        query_id = @context.match(/^query_(\d+)$/)[1]
        Query.find(query_id)
      else
        nil
      end
    end

    def update_cached_at_in_actions(actions, cached_at)
      actions.each do |action|
        if action.dig(:data, :rails_pulse__timezone_cached_at_value)
          action[:data][:rails_pulse__timezone_cached_at_value] = cached_at.iso8601
        end
      end
    end
  end
end
