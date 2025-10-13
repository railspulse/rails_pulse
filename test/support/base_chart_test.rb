require "test_helper"
require_relative "concerns/chart_data_contract"
require_relative "chart_factory_helpers"

class BaseChartTest < ActiveSupport::TestCase
  include ChartDataContract
  include ChartFactoryHelpers

  def setup
    ENV["TEST_TYPE"] = "unit"

    # Ensure tables exist before running chart tests
    DatabaseHelpers.ensure_test_tables_exist

    # Clean up any existing data for isolated tests
    cleanup_chart_test_data

    super
  end

  def teardown
    cleanup_chart_test_data
    super
  end

  protected

  # Create a route for test requests
  def create_test_route(method: "GET", path: "/api/test")
    RailsPulse::Route.find_or_create_by(method: method, path: path)
  end

  # Create a request with specified attributes
  def create_test_request(route:, occurred_at:, duration:, status: 200, is_error: false)
    RailsPulse::Request.create!(
      route: route,
      occurred_at: occurred_at,
      duration: duration,
      status: status,
      is_error: is_error,
      request_uuid: SecureRandom.uuid
    )
  end

  # Create requests spread across multiple days
  def create_requests_over_days(count_per_day: 5, days_back: 14, base_duration: 100)
    route = create_test_route

    requests = []
    (0...days_back).each do |days_ago|
      date = days_ago.days.ago.beginning_of_day

      count_per_day.times do |i|
        # Add some time variation within the day
        occurred_at = date + (i * 2).hours + rand(60).minutes

        # Add some duration variation
        duration = base_duration + rand(-20..50)

        requests << create_test_request(
          route: route,
          occurred_at: occurred_at,
          duration: duration
        )
      end
    end

    requests
  end

  # Create requests with specific duration distribution
  def create_requests_with_durations(durations, date: Time.current.beginning_of_day)
    route = create_test_route

    durations.map.with_index do |duration, i|
      occurred_at = date + (i * 10).minutes

      create_test_request(
        route: route,
        occurred_at: occurred_at,
        duration: duration
      )
    end
  end

  # Create requests for a specific day with known durations
  def create_day_requests(date, durations)
    route = create_test_route

    durations.map.with_index do |duration, i|
      # Spread requests across the day
      occurred_at = date.beginning_of_day + (i * (24.0 / durations.length)).hours

      create_test_request(
        route: route,
        occurred_at: occurred_at,
        duration: duration
      )
    end
  end

  # Create performance scenario data
  def create_performance_scenario(scenario_type = :mixed)
    route = create_test_route

    case scenario_type
    when :fast
      # All fast requests (< 100ms)
      durations = Array.new(20) { rand(10..99) }
    when :slow
      # All slow requests (100-500ms)
      durations = Array.new(20) { rand(100..500) }
    when :critical
      # All critical requests (> 500ms)
      durations = Array.new(20) { rand(500..2000) }
    when :mixed
      # Mixed performance profile
      durations = [
        *Array.new(10) { rand(10..99) },    # Fast
        *Array.new(7) { rand(100..500) },   # Slow
        *Array.new(3) { rand(500..2000) }   # Critical
      ].shuffle
    end

    create_requests_with_durations(durations)
  end

  # Assert that chart data follows expected patterns
  def assert_chart_performance_bounds(data, min_value: 0, max_value: Float::INFINITY)
    data.values.each do |value|
      assert_operator value, :>=, min_value, "Chart value #{value} is below minimum bound #{min_value}"
      assert_operator value, :<=, max_value, "Chart value #{value} is above maximum bound #{max_value}"
    end
  end

  # Assert chart data trends (increasing, decreasing, stable)
  def assert_chart_trend(data, expected_trend)
    values = data.values
    return if values.length < 2

    case expected_trend
    when :increasing
      differences = values.each_cons(2).map { |a, b| b - a }
      positive_changes = differences.count { |diff| diff > 0 }

      assert_operator positive_changes, :>, differences.length / 2, "Expected increasing trend but got values: #{values}"
    when :decreasing
      differences = values.each_cons(2).map { |a, b| b - a }
      negative_changes = differences.count { |diff| diff < 0 }

      assert_operator negative_changes, :>, differences.length / 2, "Expected decreasing trend but got values: #{values}"
    when :stable
      # Check if values are within acceptable variance
      mean = values.sum.to_f / values.length
      variance = values.map { |v| (v - mean) ** 2 }.sum / values.length
      standard_deviation = Math.sqrt(variance)

      # Values should be within 2 standard deviations for stable trend
      outliers = values.count { |v| (v - mean).abs > 2 * standard_deviation }

      assert_operator outliers, :<=, values.length * 0.1, "Expected stable trend but found #{outliers} outliers in values: #{values}"
    end
  end

  # Create time zone test scenario
  def with_time_zone(timezone)
    original_zone = Time.zone
    Time.zone = timezone
    yield
  ensure
    Time.zone = original_zone
  end

  # Benchmark chart generation performance
  def benchmark_chart_generation(chart_instance, max_time_ms: 100)
    start_time = Time.current
    data = chart_instance.to_chart_data
    end_time = Time.current

    execution_time_ms = ((end_time - start_time) * 1000).round(2)

    assert_operator execution_time_ms, :<=, max_time_ms, "Chart generation took #{execution_time_ms}ms, expected <= #{max_time_ms}ms"

    data
  end

  private

  def cleanup_chart_test_data
    # Clean up in reverse dependency order
    RailsPulse::Summary.delete_all if RailsPulse::Summary.table_exists?
    RailsPulse::Operation.delete_all if RailsPulse::Operation.table_exists?
    RailsPulse::Request.delete_all if RailsPulse::Request.table_exists?
    RailsPulse::Route.delete_all if RailsPulse::Route.table_exists?
    RailsPulse::Query.delete_all if RailsPulse::Query.table_exists?
  end
end
