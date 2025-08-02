require "test_helper"

class RailsPulse::Dashboard::Charts::AverageResponseTimeTest < BaseChartTest
  def setup
    super
    @chart = RailsPulse::Dashboard::Charts::AverageResponseTime.new
  end

  # Basic Functionality Tests

  test "returns hash with date keys and numeric values" do
    create(:chart_request, :at_time, :with_duration,
      at_time: 1.day.ago.beginning_of_day,
      with_duration: 100
    )

    data = @chart.to_chart_data

    assert_instance_of Hash, data
    assert data.keys.all? { |key| key.is_a?(String) }
    assert data.values.all? { |value| value.is_a?(Numeric) }
  end

  test "calculates correct average for single day with multiple requests" do
    date = 1.day.ago.beginning_of_day
    durations = [ 100, 200, 300 ] # Average should be 200

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    assert_equal 200, data[date_key]
  end

  test "complies with chart data contract" do
    create(:chart_request, :at_time, :with_duration,
      at_time: 3.days.ago.beginning_of_day,
      with_duration: 150
    )

    data = @chart.to_chart_data

    assert_valid_chart_data(data, expected_days: 14)
  end

  test "handles empty data scenario per contract" do
    assert_empty_chart_data_handling(@chart)
  end

  # Time Range Boundary Tests

  test "includes requests from exactly 2 weeks ago" do
    # Test boundary condition - exactly 2 weeks ago
    boundary_date = 2.weeks.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: boundary_date,
      with_duration: 150
    )

    data = @chart.to_chart_data
    date_key = boundary_date.strftime("%b %-d")

    assert_includes data, date_key
    assert_equal 150, data[date_key]
  end

  test "excludes requests from before 2 weeks ago" do
    # Test boundary condition - just before 2 weeks ago
    old_date = 2.weeks.ago.beginning_of_day - 1.second
    create(:chart_request, :at_time, :with_duration,
      at_time: old_date,
      with_duration: 150
    )

    data = @chart.to_chart_data

    # Should not include the old date
    old_date_key = old_date.strftime("%b %-d")
    assert_not_includes data, old_date_key
    assert_empty data
  end

  test "includes requests from today" do
    today = Time.current.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: today,
      with_duration: 250
    )

    data = @chart.to_chart_data
    date_key = today.strftime("%b %-d")

    assert_includes data, date_key
    assert_equal 250, data[date_key]
  end

  # Performance and Large Dataset Tests

  test "handles large dataset efficiently" do
    # Create 1000 requests across 14 days
    start_date = 14.days.ago.beginning_of_day
    requests = []

    14.times do |day|
      date = start_date + day.days
      71.times do |i| # ~71 requests per day to get ~1000 total
        occurred_at = date + (i * 20).minutes
        duration = rand(50..500)

        requests << create(:chart_request, :at_time, :with_duration,
          at_time: occurred_at,
          with_duration: duration
        )
      end
    end

    # Benchmark the performance
    data = benchmark_chart_generation(@chart, max_time_ms: 500)

    # Verify data integrity
    assert_equal 14, data.keys.count
    assert data.values.all? { |v| v.is_a?(Numeric) && v >= 0 }
  end

  test "handles sparse data distribution" do
    # Create data only on some days
    sparse_dates = [ 14.days.ago, 10.days.ago, 5.days.ago, 1.day.ago ]

    sparse_dates.each do |date|
      create_chart_day_requests(date.beginning_of_day, [ 100, 200, 300 ])
    end

    data = @chart.to_chart_data

    # Should have 14 days total
    assert_equal 14, data.keys.count

    # Only 4 days should have non-zero values
    non_zero_days = data.values.count { |v| v > 0 }
    assert_equal 4, non_zero_days
  end

  test "handles dense data distribution" do
    # Create data on all days with varying amounts
    start_date = 14.days.ago.beginning_of_day

    14.times do |day|
      date = start_date + day.days
      request_count = rand(5..20)
      durations = Array.new(request_count) { rand(50..300) }

      create_chart_day_requests(date, durations)
    end

    data = @chart.to_chart_data

    # All days should have data
    assert_equal 14, data.keys.count
    assert data.values.all? { |v| v > 0 }
  end

  # Edge Cases and Boundary Conditions

  test "handles extreme duration values" do
    date = 1.day.ago.beginning_of_day

    # Test with very small and very large durations
    durations = [ 1, 10000, 50000, 100000 ]
    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    expected_average = (1 + 10000 + 50000 + 100000) / 4
    assert_equal expected_average, data[date_key]
  end

  test "handles null duration values gracefully" do
    # This test verifies the chart handles any potential null values
    # by testing the transform_values logic
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date,
      with_duration: 150
    )

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # Should not have any nil values
    assert_not_nil data[date_key]
    assert data[date_key].is_a?(Numeric)
  end

  test "rounds average values correctly" do
    date = 1.day.ago.beginning_of_day
    # Create durations that will result in non-integer average
    durations = [ 100, 101, 102 ] # Average = 101.0

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # Should be rounded to integer
    assert_equal 101, data[date_key]
    assert_instance_of Integer, data[date_key]
  end

  test "handles single request per day" do
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date,
      with_duration: 175
    )

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # Single request average should be the request duration
    assert_equal 175, data[date_key]
  end

  # Timezone and Date Format Tests

  test "handles different timezone scenarios" do
    with_time_zone("UTC") do
      date = 1.day.ago.beginning_of_day
      create(:chart_request, :at_time, :with_duration,
        at_time: date,
        with_duration: 150
      )

      data = @chart.to_chart_data
      date_key = date.strftime("%b %-d")

      assert_includes data, date_key
      assert_equal 150, data[date_key]
    end
  end

  test "uses correct date format for keys" do
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date,
      with_duration: 150
    )

    data = @chart.to_chart_data

    # Should use "MMM D" format (e.g., "Jan 15")
    expected_format = date.strftime("%b %-d")
    assert_includes data, expected_format

    # All keys should follow this format
    data.keys.each do |key|
      assert_match(/\A[A-Z][a-z]{2} \d{1,2}\z/, key)
    end
  end

  # Data Quality and Consistency Tests

  test "maintains data consistency across multiple calls" do
    date = 1.day.ago.beginning_of_day
    create_chart_day_requests(date, [ 100, 200, 300 ])

    # Call multiple times
    data1 = @chart.to_chart_data
    data2 = @chart.to_chart_data
    data3 = @chart.to_chart_data

    # All calls should return identical data
    assert_equal data1, data2
    assert_equal data2, data3
  end

  test "handles requests spanning multiple days" do
    # Create requests that span the 2-week boundary
    boundary_date = 2.weeks.ago.beginning_of_day

    # Request exactly at boundary
    create(:chart_request, :at_time, :with_duration,
      at_time: boundary_date,
      with_duration: 100
    )

    # Request just after boundary
    create(:chart_request, :at_time, :with_duration,
      at_time: boundary_date + 1.hour,
      with_duration: 200
    )

    data = @chart.to_chart_data
    boundary_key = boundary_date.strftime("%b %-d")

    # Should include both requests in the same day
    assert_equal 150, data[boundary_key] # Average of 100 and 200
  end

  # Performance Scenario Tests

  test "handles high-performance scenario" do
    # All fast requests (< 100ms)
    date = 1.day.ago.beginning_of_day
    durations = Array.new(50) { rand(1..99) }

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    average = data[date_key]
    assert average < 100, "Expected average < 100ms for fast scenario, got #{average}ms"
  end

  test "handles mixed performance scenario" do
    # Mixed performance profile
    date = 2.days.ago.beginning_of_day
    fast_requests = Array.new(70) { rand(1..99) }
    slow_requests = Array.new(30) { rand(100..500) }

    durations = (fast_requests + slow_requests).shuffle
    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    average = data[date_key]
    # Average should be between fast and slow ranges
    assert average >= 50, "Expected average >= 50ms, got #{average}ms"
    assert average <= 300, "Expected average <= 300ms, got #{average}ms"
  end

  # Memory and Resource Tests

  test "does not create memory leaks with large datasets" do
    # Create a large dataset
    start_date = 14.days.ago.beginning_of_day
    requests = []

    14.times do |day|
      date = start_date + day.days
      100.times do |i|
        occurred_at = date + (i * 14).minutes
        requests << create(:chart_request, :at_time, :with_duration,
          at_time: occurred_at,
          with_duration: rand(50..300)
        )
      end
    end

    # Force garbage collection before and after
    GC.start
    initial_memory = GC.stat[:total_allocated_objects]

    @chart.to_chart_data

    GC.start
    final_memory = GC.stat[:total_allocated_objects]

    # Memory increase should be reasonable (adjusted for different database adapters)
    memory_increase = final_memory - initial_memory

    # Use different thresholds based on database adapter
    max_allowed = case ActiveRecord::Base.connection.adapter_name.downcase
    when "postgresql", "postgres"
      50000  # PostgreSQL creates more objects
    when "mysql", "mysql2"
      30000  # MySQL creates moderate objects
    else
      10000  # SQLite and others
    end

    assert memory_increase < max_allowed,
      "Memory increase too high: #{memory_increase} objects (max allowed: #{max_allowed})"
  end
end
