module RailsPulse
  class DashboardController < ApplicationController
    VALID_PERIODS = [ 7, 14, 30 ].freeze
    DEFAULT_PERIOD = 7

    def index
      @period = params[:period].to_i
      @period = DEFAULT_PERIOD unless VALID_PERIODS.include?(@period)

      # Get tag filter values from session
      disabled_tags = session_disabled_tags
      show_non_tagged = session[:show_non_tagged] != false

      @percentile_response_times_metric_card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period).to_metric_card
      @request_count_totals_metric_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period).to_metric_card
      @error_rates_metric_card = RailsPulse::Routes::Cards::ErrorRates.new(route: nil, disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period).to_metric_card
      @job_failure_rate_metric_card = RailsPulse::Jobs::Cards::FailureRate.new(period: @period).to_metric_card if RailsPulse.configuration.track_jobs

      # Generate chart data for inline rendering
      @response_time_percentiles_chart_data = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period).to_chart_data
      @throughput_and_errors_chart_data = RailsPulse::Dashboard::Charts::ThroughputAndErrors.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period).to_chart_data

      # Needs Attention panel
      @needs_attention = RailsPulse::Dashboard::NeedsAttention.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period).to_attention_data

      # System Health bar
      @health_summary = RailsPulse::Dashboard::HealthSummary.new(disabled_tags: disabled_tags, show_non_tagged: show_non_tagged, period: @period).to_health_data
    end
  end
end
