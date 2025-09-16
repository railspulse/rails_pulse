module RailsPulse
  class RequestsController < ApplicationController
    include ChartTableConcern

    before_action :set_request, only: :show

    def index
      unless turbo_frame_request?
        @average_response_times_metric_card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: nil).to_metric_card
        @percentile_response_times_metric_card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil).to_metric_card
        @request_count_totals_metric_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil).to_metric_card
        @error_rate_per_route_metric_card = RailsPulse::Routes::Cards::ErrorRatePerRoute.new(route: nil).to_metric_card
      end

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
      base_params = ransack_params.except(:s).merge(
        period_start_gteq: Time.at(@start_time),
        period_start_lt: Time.at(@end_time),
        summarizable_type_eq: "RailsPulse::Request",
        summarizable_id_eq: 0
      )

      # Only add duration filter if we have a meaningful threshold
      base_params[:avg_duration_gteq] = @start_duration if @start_duration && @start_duration > 0
      base_params
    end

    def build_table_ransack_params(ransack_params)
      params = ransack_params.merge(
        occurred_at_gteq: Time.at(@table_start_time),
        occurred_at_lt: Time.at(@table_end_time)
      )
      params[:duration_gteq] = @start_duration if @start_duration && @start_duration > 0
      params
    end

    def default_table_sort
      "occurred_at desc"
    end

    def build_table_results
      # Only show requests that belong to time periods where we have overall request summaries
      # This ensures the table data is consistent with the chart data
      @ransack_query.result
        .joins(:route)
        .joins(<<~SQL)
          INNER JOIN rails_pulse_summaries ON
            rails_pulse_summaries.summarizable_id = 0 AND
            rails_pulse_summaries.summarizable_type = 'RailsPulse::Request' AND
            rails_pulse_summaries.period_type = '#{period_type}' AND
            rails_pulse_requests.occurred_at >= rails_pulse_summaries.period_start AND
            rails_pulse_requests.occurred_at < rails_pulse_summaries.period_end
        SQL
        .select(
          "rails_pulse_requests.id",
          "rails_pulse_requests.occurred_at",
          "rails_pulse_requests.duration",
          "rails_pulse_requests.status",
          "rails_pulse_requests.route_id",
          "rails_pulse_routes.path"
        )
        .distinct
    end

    def set_request
      @request = Request.find(params[:id])
    end
  end
end
