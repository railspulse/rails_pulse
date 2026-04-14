# ChartTableConcern
#
# Core concern for controllers that display both charts and tables (routes, requests, queries, jobs).
# Orchestrates time range setup, chart generation, table queries, and zoom/filter handling.
# Includes TimeRangeConcern, ResponseRangeConcern, and ZoomRangeConcern for filter management.
#
# Controllers including this concern must implement:
# - chart_model, table_model, chart_definitions, default_table_sort, build_table_results
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

    unless partial_request?
      # Setup chart data first using original time range (no sorting from table)
      setup_chart_data(ransack_params)
      @has_chart_data = meaningful_chart_data?
    end

    # Setup table data using zoom parameters if present, otherwise use chart parameters
    setup_table_data(ransack_params)

    # Set flag to determine if we have meaningful data to display
    @has_data = has_meaningful_data?
  end

  # Sets up chart data for all chart types defined by the controller.
  # Generates multiple chart instances and stores them in instance variables.
  # Controllers override `chart_definitions` to specify which charts to render.
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

    # Generate all chart types defined by the controller
    chart_definitions.each do |ivar_name, chart_class|
      instance_variable_set(
        "@#{ivar_name}",
        chart_class.new(**common_options).to_chart_data
      )
    end

    # Backward compatibility: first chart becomes @chart_data
    @chart_data = instance_variable_get("@#{chart_definitions.keys.first}") if chart_definitions.any?
  end

  def setup_table_data(ransack_params)
    table_ransack_params = build_table_ransack_params(ransack_params)
    @ransack_query = table_model.ransack(table_ransack_params)
    @ransack_query.sorts = default_table_sort if @ransack_query.sorts.empty?

    table_results = build_table_results
    handle_pagination

    @pagination, @table_data = paginate(table_results, limit: session_pagination_limit)
  end

  def setup_zoom_range_data
    @zoom_start, @zoom_end, @table_start_time, @table_end_time = setup_zoom_range(@start_time, @end_time)
  end

  def setup_time_and_response_ranges
    @start_time, @end_time, @selected_time_range, @time_diff_hours = setup_time_range
    @start_duration, @selected_response_range = setup_duration_range
  end


  def period_type
    # Default to :day for "recent" mode or when time_diff isn't set
    return :day if @time_diff_hours.nil?
    @time_diff_hours <= 25 ? :hour : :day
  end

  def meaningful_chart_data?
    return false unless @chart_data.is_a?(Hash) && @chart_data.key?(:series)

    @chart_data[:series].any? { |series|
      !series[:name].to_s.include?(" SLO ") &&
        series[:data].any? { |v| v.to_f > 0 }
    }
  end

  def has_meaningful_data?
    has_chart_data = if @chart_data.is_a?(Hash) && @chart_data.key?(:series)
      # New multi-series chart format (line charts)
      # Exclude SLO series as it always has positive threshold values
      @chart_data[:series].any? { |series| !series[:name].to_s.include?(" SLO ") && series[:data].any? { |v| v.to_f > 0 } }
    elsif @chart_data.is_a?(Hash)
      # Old simple hash format (bar charts)
      @chart_data.values.any? { |v| v.is_a?(Numeric) && v > 0 }
    else
      false
    end
    has_table_data = @table_data && @table_data.any?
    has_chart_data || has_table_data
  end

  def handle_pagination
    set_pagination_limit(params[:limit]) if params[:limit].present?
  end

  # Helper method to determine if we're on a show action
  def show_action?
    action_name == "show"
  end

  # Builds ransack parameters for chart queries
  # Common pattern: time range + optional duration filter + resource scope
  # Handles "recent" mode where @start_time/@end_time may be nil
  def build_chart_ransack_params(ransack_params)
    base_params = ransack_params.except(:s)

    # Add time filters if we have time boundaries (not in "recent" mode)
    if @start_time && @end_time
      base_params.merge!(
        period_start_gteq: Time.at(@start_time),
        period_start_lt: Time.at(@end_time)
      )
    end

    # Add summarizable_type filter for polymorphic associations (queries, jobs)
    base_params.merge!(summarizable_type_eq: summarizable_type) if summarizable_type

    # Only add duration filter if we have a meaningful threshold
    base_params[:avg_duration_gteq] = @start_duration if @start_duration && @start_duration > 0

    # Scope to specific resource on show pages
    if show_action?
      base_params.merge(summarizable_id_eq: current_resource.id)
    else
      base_params
    end
  end

  # Builds ransack parameters for table queries
  # Different logic for index (summaries) vs show (individual records)
  def build_table_ransack_params(ransack_params)
    if show_action?
      build_show_table_ransack_params(ransack_params)
    else
      build_index_table_ransack_params(ransack_params)
    end
  end

  # Builds table params for show pages (individual records like Request, JobRun)
  # Handles "recent" mode where time boundaries may be nil
  def build_show_table_ransack_params(ransack_params)
    params = ransack_params.dup

    # Add time filters if we have time boundaries (not in "recent" mode)
    if @table_start_time && @table_end_time
      params.merge!(
        occurred_at_gteq: Time.at(@table_start_time),
        occurred_at_lt: Time.at(@table_end_time)
      )
    end

    params.merge!(show_resource_filter)
    params[:duration_gteq] = @start_duration if @start_duration && @start_duration > 0
    params
  end

  # Builds table params for index pages (summary records)
  # Handles "recent" mode where time boundaries may be nil
  def build_index_table_ransack_params(ransack_params)
    params = ransack_params.dup

    # Add time filters if we have time boundaries (not in "recent" mode)
    if @table_start_time && @table_end_time
      params.merge!(
        period_start_gteq: Time.at(@table_start_time),
        period_start_lt: Time.at(@table_end_time)
      )
    end

    params.merge!(summarizable_type_eq: summarizable_type) if summarizable_type
    params[:avg_duration_gteq] = @start_duration if @start_duration && @start_duration > 0
    params
  end

  # Abstract methods - must be implemented by including controllers

  # Returns the ActiveRecord model used for chart queries (usually Summary)
  def chart_model
    raise NotImplementedError, "#{self.class} must implement #chart_model"
  end

  # Returns the ActiveRecord model used for table queries (varies by action)
  def table_model
    raise NotImplementedError, "#{self.class} must implement #table_model"
  end

  # DEPRECATED: Use chart_definitions instead
  # Returns the primary chart class for backward compatibility
  def chart_class
    raise NotImplementedError, "#{self.class} must implement #chart_class"
  end

  # Returns a hash of { instance_variable_name: ChartClass }
  # Example: { response_time_chart_data: Routes::Charts::ResponseTime }
  def chart_definitions
    raise NotImplementedError, "#{self.class} must implement #chart_definitions"
  end

  # Returns options passed to chart classes (e.g., { route: @route })
  def chart_options
    {}
  end

  # Returns the default sort order for tables
  def default_table_sort
    raise NotImplementedError, "#{self.class} must implement #default_table_sort"
  end

  # Returns the table query results (may include joins, filters, etc.)
  def build_table_results
    raise NotImplementedError, "#{self.class} must implement #build_table_results"
  end

  # Returns the summarizable_type for polymorphic associations (nil for routes)
  def summarizable_type
    nil
  end

  # Returns the ransack filter for scoping to a specific resource on show pages
  # Example: { route_id_eq: @route.id }
  def show_resource_filter
    raise NotImplementedError, "#{self.class} must implement #show_resource_filter" if show_action?
  end

  # Override in show actions to return the current resource (e.g., @route, @query)
  def current_resource
    nil
  end
end
