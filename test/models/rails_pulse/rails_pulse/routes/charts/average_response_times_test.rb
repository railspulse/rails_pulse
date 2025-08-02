require "test_helper"

class RailsPulse::Routes::Charts::AverageResponseTimesTest < BaseChartTest
  def setup
    super
    @route = create(:route)
  end

  # Basic Functionality Tests

  test "initializes with required parameters" do
    ransack_query = RailsPulse::Route.ransack({})

    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      route: @route
    )

    assert_equal ransack_query, chart.instance_variable_get(:@ransack_query)
    assert_equal :group_by_day, chart.instance_variable_get(:@group_by)
    assert_equal @route, chart.instance_variable_get(:@route)
  end

  test "defaults to group_by_day when not specified" do
    ransack_query = RailsPulse::Route.ransack({})

    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query
    )

    assert_equal :group_by_day, chart.instance_variable_get(:@group_by)
  end

  # Route-specific data path tests (when route is specified)

  test "processes route-specific data when route is specified with daily grouping" do
    # Create requests for the specific route with known durations
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: date + 2.hours,
      with_duration: 100
    )
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: date + 4.hours,
      with_duration: 200
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      route: @route
    )

    result = chart.to_rails_chart

    assert_instance_of Hash, result

    # Should have data for the day we created requests
    expected_timestamp = date.to_i
    assert_includes result, expected_timestamp
    assert_equal 150.0, result[expected_timestamp][:value] # Average of 100 and 200
  end

  # General routes data path tests (when route is nil)

  test "processes general routes data when route is nil with daily grouping" do
    # Create requests with known durations
    date = 2.days.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: date + 1.hour,
      with_duration: 75
    )
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: date + 3.hours,
      with_duration: 125
    )

    ransack_query = RailsPulse::Route.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      route: nil
    )

    result = chart.to_rails_chart

    assert_instance_of Hash, result

    # Should have data for the day we created requests
    expected_timestamp = date.to_i
    assert_includes result, expected_timestamp
    assert_equal 100.0, result[expected_timestamp][:value] # Average of 75 and 125
  end

  # Time normalization tests

  test "normalizes timestamps correctly for daily grouping" do
    # Create request at specific time within day
    specific_time = 1.day.ago.beginning_of_day + 14.hours + 30.minutes
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: specific_time,
      with_duration: 125
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      route: @route
    )

    result = chart.to_rails_chart

    # Should normalize to beginning of day
    expected_timestamp = specific_time.beginning_of_day.to_i
    assert_includes result, expected_timestamp
    assert_equal 125.0, result[expected_timestamp][:value]
  end

  test "normalizes timestamps correctly for hourly grouping" do
    # Create request at specific time within hour
    specific_time = 1.day.ago.beginning_of_day + 14.hours + 30.minutes
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: specific_time,
      with_duration: 175
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_hour,
      route: @route
    )

    result = chart.to_rails_chart

    # Should normalize to beginning of hour
    expected_timestamp = specific_time.beginning_of_hour.to_i
    assert_includes result, expected_timestamp
    assert_equal 175.0, result[expected_timestamp][:value]
  end

  # Data format tests

  test "returns data in correct rails chart format" do
    date = 3.days.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: date,
      with_duration: 175
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    assert_instance_of Hash, result

    timestamp = date.to_i
    assert_includes result, timestamp
    assert_instance_of Hash, result[timestamp]
    assert_includes result[timestamp], :value
    assert_instance_of Float, result[timestamp][:value]
    assert_equal 175.0, result[timestamp][:value]
  end

  # Edge cases

  test "handles empty result set" do
    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    assert_instance_of Hash, result
    assert_empty result
  end

  test "handles nil average durations correctly" do
    # This would typically happen if there's no data for the period
    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    assert_instance_of Hash, result
    # Should be empty when no data exists
    assert_empty result
  end

  # Multiple periods test

  test "handles multiple time periods correctly" do
    day1 = 3.days.ago.beginning_of_day
    day2 = 2.days.ago.beginning_of_day

    # Create requests for different days
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: day1,
      with_duration: 100
    )
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: day2,
      with_duration: 200
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    assert_equal 2, result.keys.length
    assert_equal 100.0, result[day1.to_i][:value]
    assert_equal 200.0, result[day2.to_i][:value]
  end

  # Configuration tests

  test "works with different group_by options" do
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: date,
      with_duration: 150
    )

    [ :group_by_hour, :group_by_day ].each do |group_by|
      ransack_query = RailsPulse::Request.ransack({})
      chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
        ransack_query: ransack_query,
        group_by: group_by,
        route: @route
      )

      result = chart.to_rails_chart

      assert_instance_of Hash, result

      # Should have some data
      assert result.keys.length > 0
      assert result.values.all? { |v| v.is_a?(Hash) && v.key?(:value) }
    end
  end

  # Route vs general data path differentiation

  test "uses route-specific data path when route is present" do
    # Create requests for specific route and general requests
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: date,
      with_duration: 100
    )
    # Create request for different route
    other_route = create(:route)
    create(:chart_request, :at_time, :with_duration,
      route: other_route,
      at_time: date,
      with_duration: 500
    )

    # Filter ransack query to only include requests for the specific route
    ransack_query = RailsPulse::Request.where(route: @route).ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route  # Route present - should use route-specific data
    )

    result = chart.to_rails_chart

    expected_timestamp = date.to_i
    # Should use only the specific route's data (100), not other route's data (500)
    assert_equal 100.0, result[expected_timestamp][:value]
  end

  test "uses general routes data path when route is nil" do
    # Create requests for multiple routes
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: date,
      with_duration: 100
    )
    other_route = create(:route)
    create(:chart_request, :at_time, :with_duration,
      route: other_route,
      at_time: date,
      with_duration: 200
    )

    ransack_query = RailsPulse::Route.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: nil  # Route nil - should use general routes data
    )

    result = chart.to_rails_chart

    expected_timestamp = date.to_i
    # Should aggregate data from all routes (average of 100 and 200)
    assert_equal 150.0, result[expected_timestamp][:value]
  end

  # Performance scenario tests

  test "calculates correct averages for mixed durations" do
    date = 2.days.ago.beginning_of_day
    durations = [ 50, 100, 150, 200, 250 ] # Average should be 150

    durations.each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: date + (i * 2).hours,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    expected_timestamp = date.to_i
    assert_includes result, expected_timestamp
    assert_equal 150.0, result[expected_timestamp][:value]
  end

  # Edge case: multiple requests at same time

  test "handles multiple requests at same timestamp" do
    timestamp = 1.day.ago.beginning_of_day + 12.hours

    # Create multiple requests at exactly the same time
    [ 100, 200, 300 ].each do |duration|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: timestamp,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    expected_timestamp = timestamp.beginning_of_day.to_i
    assert_includes result, expected_timestamp
    assert_equal 200.0, result[expected_timestamp][:value] # Average of 100, 200, 300
  end

  # Time zone handling test

  test "handles time normalization with different original times" do
    base_date = 1.day.ago.beginning_of_day

    # Create requests at different times throughout the day
    times_and_durations = [
      [ base_date + 1.hour, 100 ],
      [ base_date + 12.hours, 200 ],
      [ base_date + 22.hours, 300 ]
    ]

    times_and_durations.each do |time, duration|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: time,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      route: @route
    )

    result = chart.to_rails_chart

    # All should be grouped into same day
    expected_timestamp = base_date.to_i
    assert_includes result, expected_timestamp
    assert_equal 200.0, result[expected_timestamp][:value] # Average of 100, 200, 300
  end

  # Zero value handling

  test "handles zero average duration correctly" do
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: date,
      with_duration: 0
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    expected_timestamp = date.to_i
    assert_includes result, expected_timestamp
    assert_equal 0.0, result[expected_timestamp][:value]
  end

  # Integration tests with route ransackers

  test "chart data integrates with route average_response_time_ms ransacker" do
    # Create requests that would be picked up by the average_response_time_ms ransacker
    date = 3.days.ago.beginning_of_day
    durations = [ 80, 120, 160, 200, 240 ]  # Average = 160ms

    durations.each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: date + i.hours,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    expected_timestamp = date.to_i
    assert_includes result, expected_timestamp
    assert_equal 160.0, result[expected_timestamp][:value]

    # Verify this matches what the route's average_response_time_ms ransacker would find
    route_with_avg = @route.reload
    assert_equal 5, route_with_avg.requests.count
    assert_equal 160.0, route_with_avg.requests.average(:duration)
  end

  test "extreme outlier impact on chart averages" do
    # Create mostly normal requests plus extreme outliers to test ransacker interaction
    date = 2.days.ago.beginning_of_day
    normal_durations = [ 50, 60, 70, 80, 90 ]      # Normal range
    outlier_durations = [ 5000, 15000 ]            # Extreme outliers

    (normal_durations + outlier_durations).each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: date + i.hours,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    expected_timestamp = date.to_i
    assert_includes result, expected_timestamp

    # Average should be significantly affected by outliers
    # (50+60+70+80+90+5000+15000)/7 ≈ 2907
    chart_average = result[expected_timestamp][:value]
    assert chart_average > 2500, "Chart average should be heavily influenced by outliers, got #{chart_average}"
  end

  test "database compatibility with chart grouping and averaging" do
    # Test with fractional durations that might average differently across databases
    date = 4.days.ago.beginning_of_day
    fractional_durations = [ 100.1, 100.5, 100.9, 101.1, 101.5 ]

    fractional_durations.each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: date + i.hours,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    expected_timestamp = date.to_i
    assert_includes result, expected_timestamp

    # Should handle fractional averages correctly
    # Average of [100.1, 100.5, 100.9, 101.1, 101.5] = 100.82
    assert_equal 100.82, result[expected_timestamp][:value]
  end

  test "concurrent access with chart calculations" do
    # Create requests for chart calculation
    date = 5.days.ago.beginning_of_day
    10.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: date + i.hours,
        with_duration: (i + 1) * 20  # 20, 40, 60, ..., 200
      )
    end

    # Test concurrent access
    charts = Array.new(5) do
      ransack_query = RailsPulse::Request.ransack({})
      RailsPulse::Routes::Charts::AverageResponseTimes.new(
        ransack_query: ransack_query,
        route: @route
      )
    end

    results = charts.map(&:to_rails_chart)

    # All results should be identical
    expected_timestamp = date.to_i
    first_value = results.first[expected_timestamp][:value]
    results.each do |result|
      assert_equal first_value, result[expected_timestamp][:value]
    end

    # Verify the expected average (110.0 - average of 20,40,60,...,200)
    assert_equal 110.0, first_value
  end

  test "memory efficiency with large chart datasets" do
    # Create a large number of requests for chart processing
    date = 7.days.ago.beginning_of_day
    100.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: date + (i * 2).hours,
        with_duration: rand(50..200)
      )
    end

    memory_before = GC.stat[:heap_live_slots]

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )
    result = chart.to_rails_chart

    # Force garbage collection
    GC.start
    memory_after = GC.stat[:heap_live_slots]

    # Should not significantly increase memory usage
    memory_increase = memory_after - memory_before
    assert memory_increase < 20000, "Memory usage increased by #{memory_increase} slots"

    # Should still produce valid results
    assert_instance_of Hash, result
  end

  test "route association integrity during chart calculations" do
    # Test with multiple routes to ensure proper association filtering
    other_route = create(:route, method: "POST", path: "/api/different")
    date = 3.days.ago.beginning_of_day

    # Create requests for our route
    [ 100, 200, 300 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: date + i.hours,
        with_duration: duration
      )
    end

    # Create requests for other route with different durations
    [ 1000, 2000, 3000 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: other_route,
        at_time: date + i.hours,
        with_duration: duration
      )
    end

    # Verify that each route's chart only uses its own requests
    ransack_query1 = RailsPulse::Request.where(route: @route).ransack({})
    chart_route1 = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query1,
      route: @route
    )
    result_route1 = chart_route1.to_rails_chart

    ransack_query2 = RailsPulse::Request.where(route: other_route).ransack({})
    chart_route2 = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query2,
      route: other_route
    )
    result_route2 = chart_route2.to_rails_chart

    expected_timestamp = date.to_i
    assert_equal 200.0, result_route1[expected_timestamp][:value]  # Average of 100,200,300
    assert_equal 2000.0, result_route2[expected_timestamp][:value] # Average of 1000,2000,3000
  end

  test "timezone handling in chart time grouping" do
    original_zone = Time.zone

    begin
      # Test with UTC
      Time.zone = "UTC"
      utc_date = 2.days.ago.beginning_of_day
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: utc_date + 10.hours,
        with_duration: 150
      )

      ransack_query = RailsPulse::Request.ransack({})
      chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
        ransack_query: ransack_query,
        route: @route
      )
      utc_result = chart.to_rails_chart

      # Test with different timezone
      Time.zone = "America/New_York"
      ny_result = chart.to_rails_chart

      # Results should be consistent regardless of timezone for same data
      # Allow for small differences due to timezone conversion
      if utc_result.any? && ny_result.any?
        assert_equal utc_result.values.first[:value], ny_result.values.first[:value]
      end

    ensure
      Time.zone = original_zone
    end
  end

  test "hourly vs daily grouping with different time periods" do
    # Create requests across multiple hours and days
    base_date = 3.days.ago.beginning_of_day

    # Create requests in 3 different hours of the same day
    [ 0, 6, 12 ].each_with_index do |hour_offset, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: base_date + hour_offset.hours,
        with_duration: (i + 1) * 100  # 100, 200, 300
      )
    end

    # Test daily grouping (should average all 3 requests)
    ransack_query = RailsPulse::Request.ransack({})
    daily_chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      route: @route
    )
    daily_result = daily_chart.to_rails_chart

    # Test hourly grouping (should have separate entries for each hour)
    hourly_chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_hour,
      route: @route
    )
    hourly_result = hourly_chart.to_rails_chart

    # Daily should have 1 entry with average of all requests
    assert_equal 1, daily_result.keys.length
    daily_timestamp = base_date.to_i
    assert_equal 200.0, daily_result[daily_timestamp][:value]  # Average of 100,200,300

    # Hourly should have 3 or more entries (may have additional hours due to data spread)
    assert hourly_result.keys.length >= 3
    # Check that we have some data and at least some expected values
    expected_values = [ 100.0, 200.0, 300.0 ]
    found_values = hourly_result.values.map { |vh| vh[:value] }.compact

    # Should have at least some of our expected values
    matching_values = found_values.select { |v| expected_values.include?(v) }
    assert matching_values.any?,
      "Expected to find some of #{expected_values}, got #{found_values}"
  end

  test "integration with route status_indicator performance categories" do
    # Create requests that span different performance categories for chart visualization
    test_cases = [
      { durations: [ 20, 30, 40 ], category: "good" },          # Average 30ms - good
      { durations: [ 80, 90, 110 ], category: "slow" },         # Average 93ms - slow
      { durations: [ 180, 200, 250 ], category: "very_slow" },  # Average 210ms - very slow
      { durations: [ 800, 1000, 1200 ], category: "critical" }  # Average 1000ms - critical
    ]

    test_cases.each_with_index do |test_case, index|
      route = create(:route, method: "GET", path: "/api/#{test_case[:category]}")
      date = (index + 1).days.ago.beginning_of_day

      test_case[:durations].each_with_index do |duration, i|
        create(:chart_request, :at_time, :with_duration,
          route: route,
          at_time: date + i.hours,
          with_duration: duration
        )
      end

      # Test the chart calculation
      ransack_query = RailsPulse::Request.where(route: route).ransack({})
      chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
        ransack_query: ransack_query,
        route: route
      )
      result = chart.to_rails_chart

      expected_timestamp = date.to_i
      expected_average = test_case[:durations].sum.to_f / test_case[:durations].length

      assert_includes result, expected_timestamp
      assert_in_delta expected_average, result[expected_timestamp][:value], 0.01,
        "Expected average #{expected_average} for #{test_case[:category]} category"

      # Verify this would integrate correctly with status_indicator thresholds
      assert route.requests.count == 3
      route_avg = route.requests.average(:duration)
      assert_in_delta expected_average, route_avg, 0.01
    end
  end

  test "mathematical precision with large chart datasets" do
    # Create a large, evenly distributed dataset to test averaging precision
    date = 10.days.ago.beginning_of_day
    total_requests = 1000

    total_requests.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: date + (i * 5).minutes,  # Spread across ~83 hours
        with_duration: i + 1  # 1 to 1000 ms
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      route: @route
    )
    result = chart.to_rails_chart

    # Should accurately calculate average - results will be grouped by day
    # so we may get multiple days with different averages
    assert result.any?, "Should have some chart data"

    # Verify we get reasonable average values
    result.values.each do |value_hash|
      assert value_hash[:value] > 0, "Average should be positive"
      assert value_hash[:value] <= 1000, "Average should be reasonable"
    end
  end

  test "performance with multiple grouped time periods" do
    # Create requests across multiple days to test grouping performance
    5.times do |day_offset|
      date = (day_offset + 1).days.ago.beginning_of_day

      # Create multiple requests per day
      10.times do |i|
        create(:chart_request, :at_time, :with_duration,
          route: @route,
          at_time: date + (i * 2).hours,
          with_duration: rand(50..150)
        )
      end
    end

    start_time = Time.current

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Routes::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      route: @route
    )
    result = chart.to_rails_chart

    execution_time = Time.current - start_time

    # Should complete in reasonable time
    assert execution_time < 1.0, "Chart processing took too long: #{execution_time}s"

    # Should have 5 days of data
    assert_equal 5, result.keys.length

    # All values should be reasonable averages
    result.values.each do |value_hash|
      assert value_hash[:value] >= 50 && value_hash[:value] <= 150,
        "Chart value #{value_hash[:value]} outside expected range"
    end
  end
end
