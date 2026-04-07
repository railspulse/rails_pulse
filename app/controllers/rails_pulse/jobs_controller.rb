module RailsPulse
  class JobsController < ApplicationController
    include ChartTableConcern
    include TagFilterConcern

    before_action :set_job, only: :show

    def index
      setup_metric_cards
      setup_chart_and_table_data

      @available_queues = RailsPulse::Job.distinct.pluck(:queue_name).compact.sort
    end

    def show
      setup_metric_cards
      setup_chart_and_table_data
    end

    private

    def set_job
      @job = RailsPulse::Job.find(params[:id])
    end

    def setup_metric_cards
      return if turbo_frame_request?

      disabled_tags = session_disabled_tags
      show_non_tagged = session[:show_non_tagged] != false
      period = ((@end_time - @start_time) / 1.day).round
      period_type_str = period_type.to_s

      @total_runs_metric_card = RailsPulse::Jobs::Cards::TotalRuns.new(
        job: @job,
        disabled_tags: disabled_tags,
        show_non_tagged: show_non_tagged,
        period: period,
        period_type: period_type_str
      ).to_metric_card

      @failure_rate_metric_card = RailsPulse::Jobs::Cards::FailureRate.new(
        job: @job,
        disabled_tags: disabled_tags,
        show_non_tagged: show_non_tagged,
        period: period,
        period_type: period_type_str
      ).to_metric_card

      @p95_duration_metric_card = RailsPulse::Jobs::Cards::P95Duration.new(
        job: @job,
        disabled_tags: disabled_tags,
        show_non_tagged: show_non_tagged,
        period: period,
        period_type: period_type_str
      ).to_metric_card
    end

    # Override setup_chart_data to generate all 3 chart types
    def setup_chart_data(ransack_params)
      chart_ransack_params = build_chart_ransack_params(ransack_params)
      chart_ransack_query = chart_model.ransack(chart_ransack_params)

      common_options = {
        ransack_query: chart_ransack_query,
        period_type: period_type,
        start_time: @start_time,
        end_time: @end_time,
        start_duration: @start_duration,
        disabled_tags: session_disabled_tags,
        show_non_tagged: session[:show_non_tagged] != false,
        **chart_options
      }

      @duration_chart_data = Jobs::Charts::Duration.new(**common_options).to_chart_data
      @execution_volume_chart_data = Jobs::Charts::ExecutionVolume.new(**common_options).to_chart_data
      @failure_rate_chart_data = Jobs::Charts::FailureRate.new(**common_options).to_chart_data

      @chart_data = @duration_chart_data  # Backward compatibility
    end

    def chart_model
      Summary
    end

    def table_model
      show_action? ? JobRun : Summary
    end

    def chart_class
      Jobs::Charts::Duration
    end

    def chart_options
      show_action? ? { job: @job } : {}
    end

    def build_chart_ransack_params(ransack_params)
      base_params = ransack_params.except(:s).merge(
        period_start_gteq: Time.at(@start_time),
        period_start_lt: Time.at(@end_time),
        summarizable_type_eq: "RailsPulse::Job"
      )

      # Only add duration filter if we have a meaningful threshold
      base_params[:avg_duration_gteq] = @start_duration if @start_duration && @start_duration > 0

      if show_action?
        base_params.merge(summarizable_id_eq: @job.id)
      else
        base_params
      end
    end

    def build_table_ransack_params(ransack_params)
      if show_action?
        # For JobRun model on show page
        params = ransack_params.merge(
          occurred_at_gteq: Time.at(@table_start_time),
          occurred_at_lt: Time.at(@table_end_time),
          job_id_eq: @job.id
        )
        params[:duration_gteq] = @start_duration if @start_duration && @start_duration > 0
        params
      else
        # For Summary model on index page
        params = ransack_params.merge(
          period_start_gteq: Time.at(@table_start_time),
          period_start_lt: Time.at(@table_end_time),
          summarizable_type_eq: "RailsPulse::Job"
        )
        params[:avg_duration_gteq] = @start_duration if @start_duration && @start_duration > 0
        params
      end
    end

    def default_table_sort
      show_action? ? "occurred_at desc" : "count_sort desc"
    end

    def build_table_results
      if show_action?
        # For show action, query JobRun directly but join to summaries for consistency
        base_query = @ransack_query.result
          .joins(<<~SQL)
            INNER JOIN rails_pulse_summaries ON
              rails_pulse_summaries.summarizable_id = rails_pulse_job_runs.job_id AND
              rails_pulse_summaries.summarizable_type = 'RailsPulse::Job' AND
              rails_pulse_summaries.period_type = '#{period_type}' AND
              rails_pulse_job_runs.occurred_at >= rails_pulse_summaries.period_start AND
              rails_pulse_job_runs.occurred_at < rails_pulse_summaries.period_end
          SQL
        base_query.distinct
      else
        # For index action, use aggregated summaries
        Jobs::Tables::Index.new(
          ransack_query: @ransack_query,
          period_type: period_type,
          start_time: @start_time,
          params: params,
          disabled_tags: session_disabled_tags,
          show_non_tagged: session[:show_non_tagged] != false,
          queue_name: params[:queue_name]
        ).to_table
      end
    end

    def default_time_range_key
      :last_week
    end

    def duration_field
      :avg_duration
    end

    def show_action?
      action_name == "show"
    end
  end
end
