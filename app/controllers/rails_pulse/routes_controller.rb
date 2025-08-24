module RailsPulse
  class RoutesController < ApplicationController
    include ChartTableConcern

    before_action :set_route, only: :show

    def index
      setup_metric_cards
      setup_chart_and_table_data
    end

    def show
      setup_metric_cards
      setup_chart_and_table_data
    end

    private

    def setup_metric_cards
      @average_query_times_metric_card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route).to_metric_card
      @percentile_response_times_metric_card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route).to_metric_card
      @request_count_totals_metric_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route).to_metric_card
      @error_rate_per_route_metric_card = RailsPulse::Routes::Cards::ErrorRatePerRoute.new(route: @route).to_metric_card
    end

    def chart_model
      Summary
    end

    def table_model
      show_action? ? Request : Summary
    end

    def chart_class
      Routes::Charts::AverageResponseTimes
    end

    def chart_options
      show_action? ? { route: @route } : {}
    end

    def build_chart_ransack_params(ransack_params)
      base_params = ransack_params.except(:s).merge(
        duration_field => @start_duration,
        period_start_gteq: Time.at(@start_time),
        period_start_lt: Time.at(@end_time)
      )

      if show_action?
        base_params.merge(summarizable_id_eq: @route.id)
      else
        base_params
      end
    end

    def build_table_ransack_params(ransack_params)
      if show_action?
        # For Request model on show page
        ransack_params.merge(
          duration_gteq: @start_duration,
          occurred_at_gteq: Time.at(@table_start_time),
          occurred_at_lt: Time.at(@table_end_time),
          route_id_eq: @route.id
        )
      else
        # For Summary model on index page
        ransack_params.merge(
          duration_field => @start_duration,
          period_start_gteq: Time.at(@table_start_time),
          period_start_lt: Time.at(@table_end_time)
        )
      end
    end

    def default_table_sort
      show_action? ? "occurred_at desc" : "avg_duration desc"
    end

    def build_table_results
      if show_action?
        @ransack_query.result
      else
        Routes::Tables::Index.new(
          ransack_query: @ransack_query,
          period_type: period_type,
          start_time: @start_time,
          params: params
        ).to_table
      end
    end

    def duration_field
      :avg_duration
    end

    def show_action?
      action_name == "show"
    end

    def pagination_method
      show_action? ? :set_pagination_limit : :store_pagination_limit
    end

    def set_route
      @route = Route.find(params[:id])
    end
  end
end
