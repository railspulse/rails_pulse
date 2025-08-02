module RailsPulse
  class RequestsController < ApplicationController
    include ChartTableConcern

    before_action :set_request, only: :show

    def index
      setup_chart_and_table_data
    end

    def show
      @operation_timeline = RailsPulse::Requests::Charts::OperationsChart.new(@request.operations)
    end

    private

    def chart_model
      Request
    end

    def table_model
      Request
    end

    def chart_class
      Requests::Charts::AverageResponseTimes
    end

    def chart_options
      { route: true }
    end

    def build_chart_ransack_params(ransack_params)
      ransack_params.except(:s).merge(
        occurred_at_gteq: @start_time,
        occurred_at_lt: @end_time,
        duration_gteq: @start_duration
      )
    end

    def build_table_ransack_params(ransack_params)
      ransack_params.merge(
        occurred_at_gteq: @table_start_time,
        occurred_at_lt: @table_end_time,
        duration_gteq: @start_duration
      )
    end

    def default_table_sort
      "occurred_at desc"
    end

    def build_table_results
      @ransack_query.result
        .includes(:route)
        .select(
          "rails_pulse_requests.id",
          "rails_pulse_requests.occurred_at",
          "rails_pulse_requests.duration",
          "rails_pulse_requests.status",
          "rails_pulse_requests.route_id"
        )
    end

    def set_request
      @request = Request.find(params[:id])
    end
  end
end
