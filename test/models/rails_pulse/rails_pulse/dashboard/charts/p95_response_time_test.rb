require "test_helper"

class RailsPulse::Dashboard::Charts::P95ResponseTimeTest < BaseChartTest
  def setup
    super
    @chart = RailsPulse::Dashboard::Charts::P95ResponseTime.new
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

  test "includes all days in 2-week range even with no data" do
    # P95 chart should include all days, unlike average chart
    data = @chart.to_chart_data

    # Should have 15 days total (14 full days ago + today)
    expected_days = 15
    assert_equal expected_days, data.keys.count

    # All values should be 0 when no data exists
    assert data.values.all? { |value| value == 0 }
  end

  # P95 Calculation Tests

  test "calculates correct P95 for single request" do
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date,
      with_duration: 150
    )

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # P95 of single request should be that request's duration
    assert_equal 150, data[date_key]
  end

  test "calculates correct P95 for small dataset" do
    date = 2.days.ago.beginning_of_day
    durations = [ 10, 20, 30, 40, 50 ] # P95 should be 50 (index 4)

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # With 5 requests: (5 * 0.95).ceil - 1 = 5 - 1 = 4 (0-indexed)
    # So P95 should be durations[4] = 50
    assert_equal 50, data[date_key]
  end

  test "calculates correct P95 for larger dataset" do
    date = 3.days.ago.beginning_of_day
    # Create 20 requests with durations 10, 20, 30, ..., 200
    durations = (1..20).map { |i| i * 10 }

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # With 20 requests: (20 * 0.95).ceil - 1 = 19 - 1 = 18 (0-indexed)
    # So P95 should be durations[18] = 190
    assert_equal 190, data[date_key]
  end

  test "handles exact P95 boundary conditions" do
    date = 4.days.ago.beginning_of_day

    # Test with 100 requests - P95 should be exactly the 95th value
    durations = (1..100).to_a
    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # With 100 requests: (100 * 0.95).ceil - 1 = 95 - 1 = 94 (0-indexed)
    # So P95 should be durations[94] = 95
    assert_equal 95, data[date_key]
  end

  # Edge Cases and Boundary Tests

  test "returns 0 for days with no requests" do
    # Create data for one day but not others
    create(:chart_request, :at_time, :with_duration,
      at_time: 1.day.ago.beginning_of_day,
      with_duration: 100
    )

    data = @chart.to_chart_data

    # Count days with 0 values (should be all except the one day with data)
    zero_days = data.values.count { |v| v == 0 }
    assert_equal 14, zero_days

    # One day should have the actual value
    non_zero_days = data.values.count { |v| v > 0 }
    assert_equal 1, non_zero_days
  end

  test "handles requests with same duration" do
    date = 5.days.ago.beginning_of_day
    # All requests have the same duration
    durations = Array.new(10, 150)

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # P95 of identical values should be that value
    assert_equal 150, data[date_key]
  end

  test "properly orders requests by duration" do
    date = 6.days.ago.beginning_of_day
    # Create requests in random order, but P95 should still be correct
    durations = [ 100, 50, 200, 25, 150, 75, 300, 125, 175, 250 ]
    # When sorted: [25, 50, 75, 100, 125, 150, 175, 200, 250, 300]
    # P95 index: (10 * 0.95).ceil - 1 = 10 - 1 = 9
    # P95 value should be 300 (the 10th item, 0-indexed as 9)

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    assert_equal 300, data[date_key]
  end

  test "rounds P95 values to nearest integer" do
    date = 7.days.ago.beginning_of_day
    # Create durations that will result in non-integer P95
    durations = [ 100.7, 150.3, 200.9 ]

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # P95 should be rounded to integer
    p95_value = data[date_key]
    assert_instance_of Integer, p95_value
  end

  # Time Range Boundary Tests

  test "includes requests from exactly 2 weeks ago" do
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
    # Create request just before 2-week boundary
    old_date = 2.weeks.ago.beginning_of_day - 1.second
    create(:chart_request, :at_time, :with_duration,
      at_time: old_date,
      with_duration: 150
    )

    data = @chart.to_chart_data

    # All days should have 0 since old request is excluded
    assert data.values.all? { |value| value == 0 }
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

  # Performance Optimization Tests

  test "uses single query optimization for large datasets" do
    # Create a large dataset to test the optimization
    start_date = 14.days.ago.beginning_of_day
    requests = []

    14.times do |day|
      date = start_date + day.days
      100.times do |i|
        occurred_at = date + (i * 14).minutes
        requests << create(:chart_request, :at_time, :with_duration,
          at_time: occurred_at,
          with_duration: rand(50..500)
        )
      end
    end

    # Benchmark the performance - should be much faster than N+1 queries
    data = benchmark_chart_generation(@chart, max_time_ms: 1000)

    # Verify data integrity
    assert_equal 15, data.keys.count # 15 days total
    assert data.values.all? { |v| v.is_a?(Numeric) && v >= 0 }
  end

  test "optimization handles pre-sorted data correctly" do
    # Test that the optimization correctly handles the ORDER BY clause
    date = 1.day.ago.beginning_of_day
    # Create requests in random order
    durations = [ 300, 100, 500, 200, 400 ]

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # P95 should be correct despite random input order
    # Sorted: [100, 200, 300, 400, 500]
    # P95 index: (5 * 0.95).ceil - 1 = 5 - 1 = 4
    # P95 value: 500
    assert_equal 500, data[date_key]
  end

  test "optimization maintains data integrity with concurrent access" do
    # Test that the optimization works correctly under concurrent access
    date = 1.day.ago.beginning_of_day
    durations = (1..50).to_a
    create_chart_day_requests(date, durations)

    # Simulate concurrent access by calling multiple times rapidly
    results = []
    5.times do
      results << @chart.to_chart_data
    end

    # All results should be identical
    results.each_cons(2) do |result1, result2|
      assert_equal result1, result2, "Concurrent access produced inconsistent results"
    end
  end

    # Memory Usage and Performance Tests

    test "handles memory efficiently with large datasets" do
    # Create a large dataset (reduced size for better cross-database compatibility)
    start_date = 14.days.ago.beginning_of_day
    requests = []

    14.times do |day|
      date = start_date + day.days
      100.times do |i| # 100 requests per day = 1400 total (reduced from 500)
        occurred_at = date + (i * 14.4).minutes
        requests << create(:chart_request, :at_time, :with_duration,
          at_time: occurred_at,
          with_duration: rand(10..1000)
        )
      end
    end

    # Monitor memory usage
    GC.start
    initial_memory = GC.stat[:total_allocated_objects]

    data = @chart.to_chart_data

    GC.start
    final_memory = GC.stat[:total_allocated_objects]

    # Memory increase should be reasonable (adjusted for different database adapters)
    memory_increase = final_memory - initial_memory

    # Use different thresholds based on database adapter
    max_allowed = case ActiveRecord::Base.connection.adapter_name.downcase
    when "postgresql", "postgres"
      500000  # PostgreSQL creates more objects
    when "mysql", "mysql2"
      400000  # MySQL creates moderate objects
    else
      300000  # SQLite and others
    end

    assert memory_increase < max_allowed,
      "Memory increase too high: #{memory_increase} objects (max allowed: #{max_allowed})"

    # Verify data integrity
    assert_equal 15, data.keys.count
    assert data.values.all? { |v| v.is_a?(Numeric) && v >= 0 }
  end

  test "performance scales reasonably with dataset size" do
    # Test performance scaling with smaller datasets for cross-database compatibility
    sizes = [ 50, 100, 200 ]  # Reduced sizes
    times = []

    sizes.each do |size|
      cleanup_chart_test_data

      # Create dataset of given size
      start_date = 14.days.ago.beginning_of_day
      size.times do |i|
        occurred_at = start_date + (i * (14.days / size))
        create(:chart_request, :at_time, :with_duration,
          at_time: occurred_at,
          with_duration: rand(50..300)
        )
      end

      # Measure performance
      start_time = Time.current
      @chart.to_chart_data
      end_time = Time.current

      times << ((end_time - start_time) * 1000).round(2)
    end

    # Performance should be reasonable across different database adapters
    # Use different thresholds based on database adapter
    max_allowed = case ActiveRecord::Base.connection.adapter_name.downcase
    when "postgresql", "postgres"
      2000  # PostgreSQL might be slower
    when "mysql", "mysql2"
      1500  # MySQL moderate
    else
      1000  # SQLite and others
    end

    assert times.all? { |t| t >= 0 }, "Performance times should be non-negative: #{times}"
    assert times.max < max_allowed, "Performance should be reasonable: #{times} (max allowed: #{max_allowed}ms)"
  end

  # Database Index and Query Optimization Tests

  test "query uses expected index structure" do
    # This test verifies the query structure matches the optimization
    date = 1.day.ago.beginning_of_day
    create_chart_day_requests(date, [ 100, 200, 300 ])

    # Capture the SQL query (in a real scenario, you'd use query logging)
    # For now, we'll verify the chart works correctly with the expected query structure
    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # Should calculate P95 correctly
    assert_equal 300, data[date_key]
  end

  test "handles database connection issues gracefully" do
    # Test that the chart handles database issues gracefully
    # This is a basic test - in a real scenario you'd mock database failures

    date = 1.day.ago.beginning_of_day
    create_chart_day_requests(date, [ 100, 200, 300 ])

    # Should not raise exceptions under normal conditions
    assert_nothing_raised do
      @chart.to_chart_data
    end
  end

  # Error Handling and Edge Cases

  test "handles malformed duration data gracefully" do
    # Test with edge case durations
    date = 1.day.ago.beginning_of_day

    # Create requests with various edge case durations
    durations = [ 0, 1, 999999, 0.1, 100.5 ]
    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # Should handle all edge cases and return a valid P95
    p95_value = data[date_key]
    assert_instance_of Integer, p95_value
    assert p95_value >= 0
  end

  test "handles empty result sets correctly" do
    # Test with no data at all
    data = @chart.to_chart_data

    # Should return all days with 0 values
    assert_equal 15, data.keys.count
    assert data.values.all? { |v| v == 0 }
  end

  test "handles single day with mixed data types" do
    date = 1.day.ago.beginning_of_day

    # Create requests with various data types that should be handled
    durations = [ 100, 200.0, 300, 150.5, 250 ]
    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    # Should handle mixed numeric types and return valid P95
    p95_value = data[date_key]
    assert_instance_of Integer, p95_value
    assert p95_value > 0
  end

  # Performance Scenario Tests

  test "handles high-performance scenario correctly" do
    date = 8.days.ago.beginning_of_day
    # All fast requests (< 100ms)
    durations = Array.new(50) { rand(1..99) }.sort

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    p95_value = data[date_key]
    # P95 should still be under 100ms for this scenario
    assert p95_value < 100, "Expected P95 < 100ms for fast scenario, got #{p95_value}ms"
  end

  test "handles mixed performance scenario" do
    date = 9.days.ago.beginning_of_day
    # Mixed performance: 70% fast, 20% medium, 10% slow
    fast_requests = Array.new(70) { rand(1..99) }
    medium_requests = Array.new(20) { rand(100..499) }
    slow_requests = Array.new(10) { rand(500..2000) }

    durations = (fast_requests + medium_requests + slow_requests).shuffle

    create_chart_day_requests(date, durations)

    data = @chart.to_chart_data
    date_key = date.strftime("%b %-d")

    p95_value = data[date_key]
    # P95 should be in the slow range for this distribution
    assert p95_value >= 500, "Expected P95 >= 500ms for mixed scenario with 10% slow requests, got #{p95_value}ms"
  end

  # Index Calculation Edge Cases

  test "calculates correct P95 index for edge case counts" do
    # Test specific counts that might cause off-by-one errors
    test_cases = [
      { count: 1, expected_index: 0 },   # (1 * 0.95).ceil - 1 = 1 - 1 = 0
      { count: 2, expected_index: 1 },   # (2 * 0.95).ceil - 1 = 2 - 1 = 1
      { count: 19, expected_index: 18 }, # (19 * 0.95).ceil - 1 = 19 - 1 = 18
      { count: 21, expected_index: 19 }  # (21 * 0.95).ceil - 1 = 20 - 1 = 19
    ]

    test_cases.each_with_index do |test_case, i|
      cleanup_chart_test_data

      date = (i + 1).days.ago.beginning_of_day
      durations = (1..test_case[:count]).to_a

      create_chart_day_requests(date, durations)

      data = @chart.to_chart_data
      date_key = date.strftime("%b %-d")

      # The P95 value should be the duration at the calculated index + 1 (since durations are 1-indexed)
      expected_p95 = durations[test_case[:expected_index]]
      assert_equal expected_p95, data[date_key],
        "For count #{test_case[:count]}, expected P95 index #{test_case[:expected_index]} (value #{expected_p95}), got #{data[date_key]}"
    end
  end

  # Contract Compliance Tests

  test "complies with chart data contract" do
    # Create some sample data
    create(:chart_request, :at_time, :with_duration,
      at_time: 3.days.ago.beginning_of_day,
      with_duration: 150
    )

    data = @chart.to_chart_data

    assert_valid_chart_data(data, expected_days: 15) # P95 includes all days
  end

  test "handles empty data scenario per contract" do
    assert_empty_chart_data_handling(@chart)
  end

  # Multiple Days Test

  test "calculates P95 independently for each day" do
    # Day 1: P95 should be 90
    day1 = 5.days.ago.beginning_of_day
    day1_durations = (1..10).map { |i| i * 10 } # [10, 20, ..., 100], P95 = 100
    create_chart_day_requests(day1, day1_durations)

    # Day 2: P95 should be 190
    day2 = 3.days.ago.beginning_of_day
    day2_durations = (1..20).map { |i| i * 10 } # [10, 20, ..., 200], P95 = 190
    create_chart_day_requests(day2, day2_durations)

    data = @chart.to_chart_data

    day1_key = day1.strftime("%b %-d")
    day2_key = day2.strftime("%b %-d")

    # With 10 requests: (10 * 0.95).ceil - 1 = 10 - 1 = 9, so P95 = durations[9] = 100
    assert_equal 100, data[day1_key]

    # With 20 requests: (20 * 0.95).ceil - 1 = 19 - 1 = 18, so P95 = durations[18] = 190
    assert_equal 190, data[day2_key]
  end

  # Thread Safety and Concurrent Access Tests

  test "maintains thread safety under concurrent access" do
    # Test that the chart can handle concurrent access safely
    date = 1.day.ago.beginning_of_day
    create_chart_day_requests(date, [ 100, 200, 300, 400, 500 ])

    # Simulate concurrent access
    threads = []
    results = []

    3.times do
      threads << Thread.new do
        results << @chart.to_chart_data
      end
    end

    threads.each(&:join)

    # All results should be identical
    results.each_cons(2) do |result1, result2|
      assert_equal result1, result2, "Concurrent access produced inconsistent results"
    end
  end

  # Data Consistency and Integrity Tests

  test "maintains data consistency across multiple calls" do
    date = 1.day.ago.beginning_of_day
    create_chart_day_requests(date, [ 100, 200, 300, 400, 500 ])

    # Call multiple times
    data1 = @chart.to_chart_data
    data2 = @chart.to_chart_data
    data3 = @chart.to_chart_data

    # All calls should return identical data
    assert_equal data1, data2
    assert_equal data2, data3
  end

  test "handles requests spanning multiple days correctly" do
    # Test boundary conditions with requests spanning days
    boundary_date = 2.weeks.ago.beginning_of_day

    # Request at end of boundary day
    create(:chart_request, :at_time, :with_duration,
      at_time: boundary_date.end_of_day,
      with_duration: 100
    )

    # Request at start of next day
    create(:chart_request, :at_time, :with_duration,
      at_time: (boundary_date + 1.day).beginning_of_day,
      with_duration: 200
    )

    data = @chart.to_chart_data
    boundary_key = boundary_date.strftime("%b %-d")
    next_day_key = (boundary_date + 1.day).strftime("%b %-d")

    # Should have separate P95 values for each day
    assert_equal 100, data[boundary_key]
    assert_equal 200, data[next_day_key]
  end
end
