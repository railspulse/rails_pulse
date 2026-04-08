require "test_helper"

class RailsPulse::StatusHelperTest < ActionView::TestCase
  include RailsPulse::ApplicationHelper
  include RailsPulse::StatusHelper
  fixtures :rails_pulse_routes, :rails_pulse_requests, :rails_pulse_operations

  def setup
    # Use existing fixture data
    @test_route = rails_pulse_routes(:api_users)
    @test_request = rails_pulse_requests(:users_request_1)
    super
  end

  # ============================================================================
  # operation_status_indicator Tests
  # ============================================================================

  private

  def create_test_operation(operation_type, duration)
    RailsPulse::Operation.create!(
      request: @test_request,
      operation_type: operation_type,
      label: "Test #{operation_type}",
      duration: duration,
      start_time: Time.current.to_f,
      occurred_at: Time.current
    )
  end

  # ============================================================================
  # operation_status_indicator Tests - Threshold Variations
  # ============================================================================

  test "operation_status_indicator uses sql thresholds" do
    operation = create_test_operation("sql", 75) # Above sql slow threshold
    result = operation_status_indicator(operation)

    assert_includes result, "alert-triangle"
    assert_includes result, "text-yellow-600"
  end

  test "operation_status_indicator uses template thresholds" do
    operation = create_test_operation("template", 200) # Above template very slow threshold
    result = operation_status_indicator(operation)

    assert_includes result, "alert-circle"
    assert_includes result, "text-orange-600"
  end

  test "operation_status_indicator uses controller thresholds" do
    operation = create_test_operation("controller", 600) # Above controller very slow threshold
    result = operation_status_indicator(operation)

    assert_includes result, "alert-circle"
    assert_includes result, "text-orange-600"
  end

  test "operation_status_indicator uses cache thresholds" do
    operation = create_test_operation("cache_read", 25) # Above cache slow threshold
    result = operation_status_indicator(operation)

    assert_includes result, "alert-triangle"
    assert_includes result, "text-yellow-600"
  end

  test "operation_status_indicator uses http thresholds" do
    operation = create_test_operation("http", 750) # Above http slow threshold
    result = operation_status_indicator(operation)

    assert_includes result, "alert-triangle"
    assert_includes result, "text-yellow-600"
  end

  test "operation_status_indicator uses job thresholds" do
    operation = create_test_operation("job", 2000) # Above job slow threshold
    result = operation_status_indicator(operation)

    assert_includes result, "alert-triangle"
    assert_includes result, "text-yellow-600"
  end

  test "operation_status_indicator uses mailer thresholds" do
    operation = create_test_operation("mailer", 750) # Above mailer slow threshold
    result = operation_status_indicator(operation)

    assert_includes result, "alert-triangle"
    assert_includes result, "text-yellow-600"
  end

  test "operation_status_indicator uses storage thresholds" do
    operation = create_test_operation("storage", 750) # Above storage slow threshold
    result = operation_status_indicator(operation)

    assert_includes result, "alert-triangle"
    assert_includes result, "text-yellow-600"
  end

  test "operation_status_indicator uses default thresholds for unknown type" do
    operation = create_test_operation("sql", 200) # Above default very slow threshold
    # Temporarily change the operation type to test unknown type behavior
    operation.update_column(:operation_type, "unknown")
    result = operation_status_indicator(operation)

    assert_includes result, "alert-triangle" # Still warning because 200 < 300 (very_slow)
    assert_includes result, "text-yellow-600"
  end

  # ============================================================================
  # operations_performance_breakdown Tests
  # ============================================================================

  test "operations_performance_breakdown calculates percentages correctly" do
    operations = [
      create_test_operation("sql", 100),
      create_test_operation("template", 50),
      create_test_operation("controller", 50)
    ]

    breakdown = operations_performance_breakdown(operations)

    assert_in_delta(50.0, breakdown[:database], 0.1)   # 100/200 * 100
    assert_in_delta(25.0, breakdown[:view], 0.1)       # 50/200 * 100
    assert_in_delta(25.0, breakdown[:application], 0.1) # 50/200 * 100
    assert_in_delta(0.0, breakdown[:other], 0.1)
  end

  test "operations_performance_breakdown with fixture operations" do
    # Use actual fixture operations
    operations = @test_request.operations

    breakdown = operations_performance_breakdown(operations)

    # Verify it returns the expected structure
    assert_kind_of Hash, breakdown
    assert breakdown.key?(:database)
    assert breakdown.key?(:view)
    assert breakdown.key?(:application)
    assert breakdown.key?(:other)

    # All percentages should sum to 100 (or close due to rounding)
    total = breakdown.values.sum
    assert_in_delta 100.0, total, 1.0
  end

  test "operations_performance_breakdown handles empty operations" do
    breakdown = operations_performance_breakdown([])
    expected = { database: 0, view: 0, application: 0, other: 0 }

    assert_equal expected, breakdown
  end

  test "operations_performance_breakdown handles zero duration" do
    operations = [ create_test_operation("sql", 0) ]
    breakdown = operations_performance_breakdown(operations)
    expected = { database: 0, view: 0, application: 0, other: 0 }

    assert_equal expected, breakdown
  end

  # ============================================================================
  # categorize_operation Tests
  # ============================================================================

  test "categorize_operation categorizes correctly" do
    assert_equal :database, categorize_operation("sql")
    assert_equal :view, categorize_operation("template")
    assert_equal :view, categorize_operation("partial")
    assert_equal :view, categorize_operation("layout")
    assert_equal :view, categorize_operation("collection")
    assert_equal :application, categorize_operation("controller")
    assert_equal :other, categorize_operation("unknown")
  end

  # ============================================================================
  # truncate_sql Tests
  # ============================================================================

  test "truncate_sql truncates long SQL" do
    long_sql = "SELECT * FROM very_long_table_name_that_exceeds_the_default_length_limit"
    result = truncate_sql(long_sql, length: 20)

    assert_equal 20, result.length
    assert_includes result, "..."
  end

  test "truncate_sql leaves short SQL unchanged" do
    short_sql = "SELECT * FROM users"
    result = truncate_sql(short_sql, length: 100)

    assert_equal short_sql, result
  end

  test "event_color returns correct colors" do
    assert_equal "#d27d6b", event_color("sql")
    assert_equal "#6c7ab9", event_color("template")
    assert_equal "#6c7ab9", event_color("partial")
    assert_equal "#6c7ab9", event_color("layout")
    assert_equal "#6c7ab9", event_color("collection")
    assert_equal "#5ba6b0", event_color("controller")
    assert_equal "#a6a6a6", event_color("unknown")
  end

  test "duration_options returns correct options for routes" do
    options = duration_options(:route)

    assert_equal 4, options.length
    assert_equal "All Routes", options[0][0]
    assert_equal :all, options[0][1]
    assert_includes options[1][0], "Slow"
    assert_equal :slow, options[1][1]
    assert_includes options[2][0], "Very Slow"
    assert_equal :very_slow, options[2][1]
    assert_includes options[3][0], "Critical"
    assert_equal :critical, options[3][1]
  end

  test "duration_options returns correct options for requests" do
    options = duration_options(:request)

    assert_equal 4, options.length
    assert_equal "All Requests", options[0][0]
    assert_equal :all, options[0][1]
    assert_includes options[1][0], "Slow"
    assert_equal :slow, options[1][1]
  end

  test "duration_options returns correct options for queries" do
    options = duration_options(:query)

    assert_equal 4, options.length
    assert_equal "All Queries", options[0][0]
    assert_equal :all, options[0][1]
    assert_includes options[1][0], "Slow"
    assert_equal :slow, options[1][1]
  end

  test "duration_options uses default route type" do
    options = duration_options

    assert_equal 4, options.length
    assert_equal "All Routes", options[0][0]
    assert_equal :all, options[0][1]
  end

  test "duration_threshold_filter_options returns correct format" do
    options = duration_threshold_filter_options(:route)

    assert_kind_of Array, options
    assert options.length > 0
    assert_equal "All Routes", options.first[0]
    assert_nil options.first[1]

    # Subsequent options should have threshold values
    assert options[1..-1].all? { |label, value| value.is_a?(Numeric) }
  end

  test "duration_threshold_filter_options for jobs uses correct label" do
    options = duration_threshold_filter_options(:job)

    assert_equal "All Job Runs", options.first[0]
  end

  test "truncate_sql handles nil input" do
    assert_raises(NoMethodError) do
      truncate_sql(nil, length: 20)
    end
  end

  test "truncate_sql handles empty string" do
    result = truncate_sql("", length: 20)

    assert_equal "", result
  end

  test "truncate_sql uses default length" do
    long_sql = "SELECT * FROM very_long_table_name_that_exceeds_the_default_length_limit"
    result = truncate_sql(long_sql)
    # The string is 72 characters, which is less than the default 100, so no truncation
    assert_equal long_sql, result
  end

  # ============================================================================
  # event_color Tests
  # ============================================================================

  test "event_color handles nil input" do
    assert_equal "#a6a6a6", event_color(nil)
  end

  test "event_color handles empty string" do
    assert_equal "#a6a6a6", event_color("")
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "categorize_operation handles nil input" do
    assert_equal :other, categorize_operation(nil)
  end

  test "operations_performance_breakdown handles nil operations" do
    assert_raises(NoMethodError) do
      operations_performance_breakdown(nil)
    end
  end
end
