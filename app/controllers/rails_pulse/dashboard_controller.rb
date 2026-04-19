module RailsPulse
  class DashboardController < ApplicationController
    include TimeRangeConcern

    def index
      # Use TimeRangeConcern to get time range (supports time range selector + all other filters)
      @start_time, @end_time, @selected_time_range, @time_diff = setup_time_range

      # Convert time range to period in days for dashboard cards/charts
      @period = ((@end_time - @start_time) / 1.day).round

      # Determine period type based on time range
      # If 24 hours or less, use hourly summaries, otherwise use daily
      @period_type = @period <= 1 ? "hour" : "day"

      # Get tag filter values from session
      disabled_tags = session_disabled_tags
      show_non_tagged = session[:show_non_tagged] != false

      @percentile_response_times_metric_card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period, period_type: @period_type).to_metric_card
      @request_count_totals_metric_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period, period_type: @period_type).to_metric_card
      @error_rates_metric_card = RailsPulse::Routes::Cards::ErrorRates.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period, period_type: @period_type).to_metric_card
      @job_failure_rate_metric_card = RailsPulse::Jobs::Cards::FailureRate.new(period: @period, period_type: @period_type).to_metric_card if RailsPulse.configuration.track_jobs

      # Generate chart data for inline rendering
      @response_time_percentiles_chart_data = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period, period_type: @period_type).to_chart_data
      @throughput_and_errors_chart_data = RailsPulse::Dashboard::Charts::ThroughputAndErrors.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period, period_type: @period_type).to_chart_data

      # Needs Attention panel
      @needs_attention = RailsPulse::Dashboard::NeedsAttention.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period).to_attention_data

      # System Health bar
      @health_summary = RailsPulse::Dashboard::HealthSummary.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period).to_health_data
    end
  end
end
