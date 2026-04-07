module RailsPulse
  class QueriesController < ApplicationController
    include ChartTableConcern
    include TagFilterConcern
    include MetricCardConcern

    before_action :set_query, only: [ :show, :analyze ]

    def index
      setup_metric_cards
      setup_chart_and_table_data
    end

    def show
      setup_metric_cards
      setup_chart_and_table_data
    end

    def analyze
      begin
        @analysis_results = QueryAnalysisService.analyze_query(@query.id)

        respond_to do |format|
          format.turbo_stream {
            render turbo_stream: turbo_stream.replace(
              "query_analysis",
              partial: "rails_pulse/queries/analysis_section",
              locals: { query: @query.reload }
            )
          }
          format.html {
            redirect_to query_path(@query), notice: "Query analysis completed successfully."
          }
        end
      rescue => e
        respond_to do |format|
          format.turbo_stream {
            render turbo_stream: turbo_stream.replace(
              "query_analysis",
              partial: "rails_pulse/queries/analysis_section",
              locals: { query: @query, error_message: "Analysis failed: #{e.message}" }
            )
          }
          format.html {
            redirect_to query_path(@query), alert: "Query analysis failed: #{e.message}"
          }
        end
      end
    end

    # Override to generate database load chart with custom parameters
    def setup_chart_data(ransack_params)
      super

      # Database load chart doesn't use ransack_query, so generate it separately
      @database_load_chart_data = Queries::Charts::DatabaseLoad.new(
        start_time: @start_time,
        end_time: @end_time,
        period_type: period_type,
        disabled_tags: session_disabled_tags,
        show_non_tagged: session[:show_non_tagged] != false
      ).to_chart_data
    end

    private

    # Metric card configuration
    def metric_card_definitions
      {
        percentile_query_times_metric_card: Queries::Cards::PercentileQueryTimes,
        execution_rate_metric_card: Queries::Cards::ExecutionRate
      }
    end

    # Override to handle database_load card which has different params
    def setup_metric_cards
      return if turbo_frame_request?

      card_params = metric_card_params

      # Setup standard metric cards
      metric_card_definitions.each do |ivar_name, card_class|
        instance_variable_set(
          "@#{ivar_name}",
          card_class.new(**card_params).to_metric_card
        )
      end

      # Database load card only shows on index page and doesn't accept query param
      if current_resource.nil?
        @database_load_metric_card = Queries::Cards::DatabaseLoad.new(
          disabled_tags: session_disabled_tags,
          show_non_tagged: session[:show_non_tagged] != false,
          period: ((@end_time - @start_time) / 1.day).round,
          period_type: period_type.to_s
        ).to_metric_card
      end
    end

    # The parameter name for passing the resource to metric cards
    def resource_key
      :query
    end

    # Chart configuration
    def chart_definitions
      {
        query_performance_chart_data: Queries::Charts::QueryPerformance,
        execution_volume_chart_data: Queries::Charts::ExecutionVolume
      }
    end

    def chart_model
      Summary
    end

    def table_model
      Summary
    end

    def chart_class
      Queries::Charts::QueryPerformance
    end

    # Pass the query to chart classes on show pages
    def chart_options
      show_action? ? { query: @query } : {}
    end

    # Queries use polymorphic summaries, so we need to filter by type
    def summarizable_type
      "RailsPulse::Query"
    end

    # Filter to scope table results to a specific query on show pages
    def show_resource_filter
      { summarizable_id_eq: @query.id, summarizable_type_eq: "RailsPulse::Query" }
    end

    # Returns the current query for metric cards and chart params
    def current_resource
      @query
    end

    def default_time_range_key
      :last_7_days
    end

    def default_table_sort
      "period_start desc"
    end

    def build_table_results
      if show_action?
        # For Summary model on show page - ransack params already include query ID and type filters
        # Summaries aren't taggable, so we don't apply tag filters here
        @ransack_query.result.where(period_type: period_type)
      else
        Queries::Tables::Index.new(
          ransack_query: @ransack_query,
          period_type: period_type,
          start_time: @start_time,
          params: params,
          disabled_tags: session_disabled_tags,
          show_non_tagged: session[:show_non_tagged] != false
        ).to_table
      end
    end

    # Override table data setup to handle custom sorting logic for index page
    def setup_table_data(ransack_params)
      table_ransack_params = build_table_ransack_params(ransack_params)
      @ransack_query = table_model.ransack(table_ransack_params)

      # Only apply default sort if not using Queries::Tables::Index (which handles its own sorting)
      if show_action?
        @ransack_query.sorts = default_table_sort if @ransack_query.sorts.empty?
      end

      table_results = build_table_results
      handle_pagination

      @pagination, @table_data = paginate(table_results, limit: session_pagination_limit)
    end

    def setup_time_and_response_ranges
      @start_time, @end_time, @selected_time_range, @time_diff_hours = setup_time_range
      @start_duration, @selected_response_range = setup_duration_range(:query)
    end

    def set_query
      @query = Query.find(params[:id])
    end
  end
end
