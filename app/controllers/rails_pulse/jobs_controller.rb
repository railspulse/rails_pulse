module RailsPulse
  class JobsController < ApplicationController
    include TagFilterConcern
    include TimeRangeConcern

    # Override TIME_RANGE_OPTIONS from TimeRangeConcern
    remove_const(:TIME_RANGE_OPTIONS) if const_defined?(:TIME_RANGE_OPTIONS)
    TIME_RANGE_OPTIONS = [
      [ "Recent", "recent" ],
      [ "Custom Range", "custom" ]
    ].freeze

    before_action :set_job, only: :show

    def index
      setup_metric_cards

      @ransack_query = RailsPulse::Job.ransack(params[:q])

      # Apply tag filters from session
      base_query = apply_tag_filters(@ransack_query.result)

      @pagy, @jobs = pagy(base_query.order(runs_count: :desc),
                          **pagy_options(session_pagination_limit),
                          overflow: :last_page)
      @table_data = @jobs
      @available_queues = RailsPulse::Job.distinct.pluck(:queue_name).compact.sort
    end

    def show
      setup_metric_cards

      ransack_params = params[:q] || {}

      # Check if user explicitly selected a time range
      time_mode = params.dig(:q, :period_start_range) || "recent"

      # Apply time range filter only if custom mode is selected
      if time_mode == "custom"
        # Get time range from TimeRangeConcern which parses custom_date_range
        @start_time, @end_time, @selected_time_range, @time_diff_hours = setup_time_range

        # Apply time filters using parsed times from concern
        ransack_params = ransack_params.merge(
          occurred_at_gteq: Time.at(@start_time),
          occurred_at_lteq: Time.at(@end_time)
        )
      else
        # Recent mode - no time filters, just rely on sort + pagination
        @selected_time_range = "recent"
      end

      @ransack_query = @job.runs.ransack(ransack_params)
      @ransack_query.sorts = "occurred_at desc" if @ransack_query.sorts.empty?

      # Apply tag filters from session
      base_query = apply_tag_filters(@ransack_query.result)

      @pagy, @recent_runs = pagy(base_query,
                                  **pagy_options(session_pagination_limit),
                                  overflow: :last_page)
      @table_data = @recent_runs
    end

    private

    def set_job
      @job = RailsPulse::Job.find(params[:id])
    end

    def setup_metric_cards
      return if turbo_frame_request?

      # Pass the job to scope the cards to the current job on the show page
      @total_runs_metric_card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job).to_metric_card
      @failure_rate_metric_card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job).to_metric_card
      @average_duration_metric_card = RailsPulse::Jobs::Cards::AverageDuration.new(job: @job).to_metric_card
    end
  end
end
