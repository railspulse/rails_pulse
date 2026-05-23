module RailsPulse
  class ExceptionsController < ApplicationController
    include TimeRangeConcern

    before_action :set_exception_group, only: :show

    def index
      @start_time, @end_time, @selected_time_range = setup_time_range

      ransack_params = (params[:q] || {}).dup
      ransack_params[:last_seen_at_gteq] = Time.zone.at(@start_time)
      ransack_params[:last_seen_at_lteq] = Time.zone.at(@end_time)

      @ransack_query = ExceptionGroup.ransack(ransack_params)
      @ransack_query.sorts = "last_seen_at desc" if @ransack_query.sorts.empty?
      @pagination, @table_data = paginate(@ransack_query.result, limit: session_pagination_limit)
    end

    def show
      occurrences = @exception_group.occurrences.order(occurred_at: :desc)
      @latest_occurrence = occurrences.first
      @pagination, @occurrences = paginate(occurrences, limit: session_pagination_limit)
    end

    private

    def set_exception_group
      @exception_group = ExceptionGroup.find(params[:id])
    end
  end
end
