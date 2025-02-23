module RailsPulse
  class RequestsController < ApplicationController
    include Pagy::Backend
    include TimeRangeConcern
    include ResponseRangeConcern

    before_action :setup_time_and_response_ranges
    before_action :set_request, only: :show

    def index
      ransack_params = params[:q] || {}
      ransack_params.merge!(
        occurred_at_gteq: @start_time,
        occurred_at_lt: @end_time,
        duration_gteq: @start_duration
      )
      @ransack_query = Request.ransack(ransack_params)

      unless turbo_frame_request?
        setup_chart_formatters
        @chart_data = Routes::Charts::AverageResponseTimes.new(
          ransack_query: @ransack_query,
          group_by: group_by,
          route: true
        ).to_rails_chart
      end

      @ransack_query.sorts = "occurred_at desc" if @ransack_query.sorts.empty?

      table_results = @ransack_query.result
        .includes(:route)
        .select(
          "rails_pulse_requests.id",
          "rails_pulse_requests.occurred_at",
          "rails_pulse_requests.duration",
          "rails_pulse_requests.status",
          "rails_pulse_requests.route_id"
        )
      store_pagination_limit(params[:limit]) if params[:limit].present?
      @pagy, @table_data = pagy(table_results, limit: session_pagination_limit)
    end

    def show
      ransack_params = params[:q] || {}
      @operation_timeline = RailsPulse::Requests::Charts::OperationsChart.new(@request.operations)
    end

    private

    def setup_time_and_response_ranges
      @start_time, @end_time, @selected_time_range, @time_diff_hours = setup_time_range
      @start_duration, @selected_response_range = setup_duration_range
    end

    def set_request
      @request = Request.find(params[:id])
    end


    def setup_chart_formatters
      @xaxis_formatter = ChartFormatters.occurred_at_as_time_or_date(@time_diff_hours)
      @tooltip_formatter = ChartFormatters.tooltip_as_time_or_date_with_marker(@time_diff_hours)
    end

    def group_by
      @time_diff_hours <= 25 ? :group_by_hour : :group_by_day
    end
  end
end
