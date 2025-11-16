module RailsPulse
  class JobRunsController < ApplicationController
    include TagFilterConcern

    before_action :set_job
    before_action :set_run, only: :show

    def index
      @ransack_query = @job.runs.ransack(params[:q])
      @pagy, @runs = pagy(@ransack_query.result.order(occurred_at: :desc), **pagy_options(session_pagination_limit))
      @table_data = @runs
    end

    def show
      @operations = @run.operations.order(:start_time)
      @operation_timeline = RailsPulse::Charts::OperationsChart.new(@operations)

      # Group operations by type
      @operations_by_type = @operations.group_by(&:operation_type)

      # SQL queries
      @sql_operations = @operations.where(operation_type: "sql")
                                   .includes(:query)
                                   .order(duration: :desc)
    end

    private

    def set_job
      @job = RailsPulse::Job.find(params[:job_id])
    end

    def set_run
      @run = @job.runs.find(params[:id])
    end
  end
end
