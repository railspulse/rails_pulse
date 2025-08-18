module RailsPulse
  class RoutesController < ApplicationController
    include ChartTableConcern

    before_action :set_route, only: :show

    def index
      setup_chart_and_table_data
    end

    def show
      setup_chart_and_table_data
    end

    private

    def chart_model
      show_action? ? Request : Route
    end

    def table_model
      show_action? ? Request : Route
    end

    def chart_class
      Routes::Charts::AverageResponseTimes
    end

    def chart_options
      show_action? ? { route: @route } : {}
    end

    def build_chart_ransack_params(ransack_params)
      base_params = ransack_params.except(:s).merge(duration_field => @start_duration)

      if show_action?
        base_params.merge(
          route_id_eq: @route.id,
          occurred_at_gteq: @start_time,
          occurred_at_lt: @end_time
        )
      else
        base_params.merge(
          requests_occurred_at_gteq: @start_time,
          requests_occurred_at_lt: @end_time
        )
      end
    end

    def build_table_ransack_params(ransack_params)
      base_params = ransack_params.merge(duration_field => @start_duration)

      if show_action?
        base_params.merge(
          route_id_eq: @route.id,
          occurred_at_gteq: Time.at(@table_start_time),
          occurred_at_lt: Time.at(@table_end_time)
        )
      else
        base_params.merge(
          requests_occurred_at_gteq: Time.at(@table_start_time),
          requests_occurred_at_lt: Time.at(@table_end_time)
        )
      end
    end

    def default_table_sort
      show_action? ? "occurred_at desc" : "average_response_time_ms desc"
    end

    def build_table_results
      if show_action?
        @ransack_query.result.select("id", "route_id", "occurred_at", "duration", "status")
      else
        Routes::Tables::Index.new(
          ransack_query: @ransack_query,
          start_time: @start_time,
          params: params
        ).to_table
      end
    end

    def duration_field
      show_action? ? :duration_gteq : :requests_duration_gteq
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
