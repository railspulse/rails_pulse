module RailsPulse
  class RequestsController < ApplicationController
    include ChartTableConcern

    before_action :set_request, only: :show

    def index
      @average_response_times_metric_card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: nil).to_metric_card
      @percentile_response_times_metric_card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil).to_metric_card
      @request_count_totals_metric_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil).to_metric_card
      @error_rate_per_route_metric_card = RailsPulse::Routes::Cards::ErrorRatePerRoute.new(route: nil).to_metric_card

      setup_chart_and_table_data
    end

    def show
      @operation_timeline = RailsPulse::Requests::Charts::OperationsChart.new(@request.operations)
    end

    private

    def chart_model
      Summary
    end

    def table_model
      Request
    end

    def chart_class
      Requests::Charts::AverageResponseTimes
    end

    def chart_options
      {}
    end

    def build_chart_ransack_params(ransack_params)
      ransack_params.except(:s).merge(
        period_start_gteq: Time.at(@start_time),
        period_start_lt: Time.at(@end_time)
      )
    end

    def build_table_ransack_params(ransack_params)
      ransack_params.merge(
        occurred_at_gteq: Time.at(@table_start_time),
        occurred_at_lt: Time.at(@table_end_time),
        duration_gteq: @start_duration
      )
    end

    def default_table_sort
      "occurred_at desc"
    end

    def build_table_results
      @ransack_query.result
        .joins(:route)
        .select(
          "rails_pulse_requests.id",
          "rails_pulse_requests.occurred_at",
          "rails_pulse_requests.duration",
          "rails_pulse_requests.status",
          "rails_pulse_requests.route_id",
          "rails_pulse_routes.path"
        )
    end

    def set_request
      @request = Request.find(params[:id])
    end
  end
end
