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

      # Get all jobs first (without pagination) to calculate percentiles
      all_jobs = base_query.to_a

      # Calculate P95/P99 percentiles from recent job runs for each job
      jobs_with_percentiles = calculate_job_percentiles(all_jobs)

      # Apply sorting if requested
      sorted_jobs = if @ransack_query.sorts.any?
        sort = @ransack_query.sorts.first
        sort_jobs_by_field(jobs_with_percentiles, sort.name, sort.dir)
      else
        # Default sort by runs_count desc
        jobs_with_percentiles.sort_by { |j| -j.runs_count }
      end

      # Paginate after sorting using custom Paginator with array
      limit = session_pagination_limit || 20
      page  = [ params[:page].to_i, 1 ].max

      @pagination = RailsPulse::Paginator.new(count: sorted_jobs.size, limit: limit, page: page)
      offset      = (@pagination.page - 1) * @pagination.limit
      @table_data = sorted_jobs[offset, @pagination.limit] || []
      @jobs = @table_data  # For backward compatibility with tests and views

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

      @pagination, @recent_runs = paginate(base_query, limit: session_pagination_limit)
      @table_data = @recent_runs
    end

    private

    def set_job
      @job = RailsPulse::Job.find(params[:id])
    end

    def calculate_job_percentiles(jobs)
      # Get job IDs for efficient querying
      job_ids = jobs.map(&:id)

      return jobs if job_ids.empty?

      # Query recent job runs (last 100 runs per job) to calculate percentiles
      recent_runs = RailsPulse::JobRun
        .where(job_id: job_ids)
        .where.not(duration: nil)
        .order(occurred_at: :desc)
        .limit(1000)  # Cap at 1000 total runs

      # Group runs by job_id
      runs_by_job = recent_runs.group_by(&:job_id)

      # Calculate P95 and P99 for each job
      jobs.map do |job|
        runs = runs_by_job[job.id] || []
        durations = runs.map(&:duration).compact.sort

        if durations.any?
          job.p95_duration = calculate_percentile(durations, 0.95)
          job.p99_duration = calculate_percentile(durations, 0.99)
        else
          job.p95_duration = 0
          job.p99_duration = 0
        end

        job
      end
    end

    def calculate_percentile(sorted_values, percentile)
      return 0 if sorted_values.empty?

      n = sorted_values.length
      index = (percentile * (n - 1)).floor
      next_index = [ (percentile * (n - 1)).ceil, n - 1 ].min

      if index == next_index
        sorted_values[index]
      else
        # Linear interpolation between values
        fraction = (percentile * (n - 1)) - index
        sorted_values[index] + (fraction * (sorted_values[next_index] - sorted_values[index]))
      end
    end

    def sort_jobs_by_field(jobs, field, direction)
      dir_mult = direction == "desc" ? -1 : 1

      case field
      when "p95_duration"
        jobs.sort_by { |j| (j.p95_duration || 0) * dir_mult }
      when "p99_duration"
        jobs.sort_by { |j| (j.p99_duration || 0) * dir_mult }
      when "runs_count"
        jobs.sort_by { |j| j.runs_count * dir_mult }
      when "failures_count"
        jobs.sort_by { |j| j.failures_count * dir_mult }
      when "retries_count"
        jobs.sort_by { |j| j.retries_count * dir_mult }
      when "name"
        direction == "desc" ? jobs.sort_by(&:name).reverse : jobs.sort_by(&:name)
      when "queue_name"
        direction == "desc" ? jobs.sort_by(&:queue_name).reverse : jobs.sort_by(&:queue_name)
      else
        jobs.sort_by { |j| -j.runs_count }  # Default to runs_count desc
      end
    end

    def setup_metric_cards
      return if turbo_frame_request?

      # Pass the job to scope the cards to the current job on the show page
      @total_runs_metric_card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job).to_metric_card
      @failure_rate_metric_card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job).to_metric_card
      @p95_duration_metric_card = RailsPulse::Jobs::Cards::P95Duration.new(job: @job).to_metric_card
    end
  end
end
