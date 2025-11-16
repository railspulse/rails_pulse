module ChartTableConcern
  extend ActiveSupport::Concern

  included do
    include TimeRangeConcern
    include ResponseRangeConcern
    include ZoomRangeConcern

    before_action :setup_time_and_response_ranges
    before_action :setup_zoom_range_data
  end

  private

  def setup_chart_and_table_data
    ransack_params = params[:q] || {}

    unless turbo_frame_request?
      # Setup chart data first using original time range (no sorting from table)
      setup_chart_data(ransack_params)
      setup_chart_formatters
    end

    # Setup table data using zoom parameters if present, otherwise use chart parameters
    setup_table_data(ransack_params)

    # Set flag to determine if we have meaningful data to display
    @has_data = has_meaningful_data?
  end

  def setup_chart_data(ransack_params)
    chart_ransack_params = build_chart_ransack_params(ransack_params)
    chart_ransack_query = chart_model.ransack(chart_ransack_params)
    @chart_data = chart_class.new(
      ransack_query: chart_ransack_query,
      period_type: period_type,
      start_time: @start_time,
      end_time: @end_time,
      start_duration: @start_duration,
      disabled_tags: session_disabled_tags,
      show_non_tagged: session[:show_non_tagged] != false,
      **chart_options
    ).to_chart_data
  end

  def setup_table_data(ransack_params)
    table_ransack_params = build_table_ransack_params(ransack_params)
    @ransack_query = table_model.ransack(table_ransack_params)
    @ransack_query.sorts = default_table_sort if @ransack_query.sorts.empty?

    table_results = build_table_results
    handle_pagination

    # Use pagy_options for version compatibility
    @pagy, @table_data = pagy(table_results, **pagy_options(session_pagination_limit))
  end

  def setup_zoom_range_data
    @zoom_start, @zoom_end, @table_start_time, @table_end_time = setup_zoom_range(@start_time, @end_time)
  end

  def setup_time_and_response_ranges
    @start_time, @end_time, @selected_time_range, @time_diff_hours = setup_time_range
    @start_duration, @selected_response_range = setup_duration_range
  end

  def setup_chart_formatters
    @xaxis_formatter = RailsPulse::ChartFormatters.period_as_time_or_date(@time_diff_hours)
    @tooltip_formatter = RailsPulse::ChartFormatters.tooltip_as_time_or_date_with_marker(@time_diff_hours)
  end

  def period_type
    @time_diff_hours <= 25 ? :hour : :day
  end

  def group_by
    @time_diff_hours <= 25 ? :group_by_hour : :group_by_day
  end

  def has_meaningful_data?
    has_chart_data = @chart_data && @chart_data.values.any? { |v| v > 0 }
    has_table_data = @table_data && @table_data.any?
    has_chart_data || has_table_data
  end

  def handle_pagination
    method = pagination_method
    send(method, params[:limit]) if params[:limit].present?
  end

  # Abstract methods - must be implemented by including controllers
  def chart_model; raise NotImplementedError; end
  def table_model; raise NotImplementedError; end
  def chart_class; raise NotImplementedError; end
  def chart_options; {}; end
  def build_chart_ransack_params(ransack_params); raise NotImplementedError; end
  def build_table_ransack_params(ransack_params); raise NotImplementedError; end
  def default_table_sort; raise NotImplementedError; end
  def build_table_results; raise NotImplementedError; end
  def pagination_method; :store_pagination_limit; end
end
