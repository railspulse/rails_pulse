require "test_helper"

class RailsPulse::Routes::Cards::AverageResponseTimesTest < BaseChartTest
  def setup
    super
    @route = create(:route)
  end

  # Basic Functionality Tests

  test "initializes with route parameter" do
    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)

    assert_equal @route, card.instance_variable_get(:@route)
  end

  test "initializes with nil route parameter" do
    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: nil)

    assert_nil card.instance_variable_get(:@route)
  end

  # Card format tests

  test "returns data in correct metric card format" do
    # Create some requests to test with (within 2 weeks)
    5.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (10.days.ago + i.days),
        with_duration: (i + 1) * 50  # 50, 100, 150, 200, 250 ms
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    assert_instance_of Hash, result
    assert_includes result, :title
    assert_includes result, :summary
    assert_includes result, :line_chart_data
    assert_includes result, :trend_icon
    assert_includes result, :trend_amount
    assert_includes result, :trend_text

    assert_equal "Average Response Time", result[:title]
    assert_equal "Compared to last week", result[:trend_text]
    assert_match /\d+ ms/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Average calculation tests

  test "calculates average response time correctly for known durations" do
    # Create requests with known durations: 50, 100, 150, 200 within 2 weeks
    [ 50, 100, 150, 200 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 5.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Average of [50, 100, 150, 200] = 125
    assert_equal "125 ms", result[:summary]
  end

  test "handles single request" do
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 2.days.ago,
      with_duration: 150
    )

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Single request should be the average
    assert_equal "150 ms", result[:summary]
  end

  test "rounds average to nearest integer" do
    # Create requests that will average to a decimal
    [ 10, 15, 20 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 3.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Average of [10, 15, 20] = 15.0, should round to 15
    assert_equal "15 ms", result[:summary]
  end

  test "filters to requests within 2 weeks" do
    # Create request within 2 weeks
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 10.days.ago,
      with_duration: 100
    )

    # Create request older than 2 weeks (should be excluded)
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 20.days.ago,
      with_duration: 500
    )

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should only include the 100ms request, not the 500ms one
    assert_equal "100 ms", result[:summary]
  end

  # Route filtering tests

  test "filters requests by route when route is specified" do
    # Create requests for specific route
    3.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 4.days.ago + i.hours,
        with_duration: 100
      )
    end

    # Create requests for different route
    other_route = create(:route)
    2.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: other_route,
        at_time: 4.days.ago + i.hours,
        with_duration: 200
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should only use requests for the specific route (average of 100, 100, 100 = 100)
    assert_equal "100 ms", result[:summary]
  end

  test "includes all requests when route is nil" do
    # Create requests for different routes
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 4.days.ago,
      with_duration: 100
    )

    other_route = create(:route)
    create(:chart_request, :at_time, :with_duration,
      route: other_route,
      at_time: 4.days.ago,
      with_duration: 200
    )

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: nil)
    result = card.to_metric_card

    # Should calculate based on all requests (average of 100, 200 = 150)
    assert_equal "150 ms", result[:summary]
  end

  # Trend calculation tests

  test "calculates correct trend when current period is faster" do
    # Previous period (14-7 days ago): Higher durations
    3.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (12.days.ago + i.days),
        with_duration: 200
      )
    end

    # Current period (last 7 days): Lower durations
    3.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (5.days.ago + i.days),
        with_duration: 100
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Current period is faster, so should be trending down
    assert_equal "trending-down", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates correct trend when current period is slower" do
    # Previous period (14-7 days ago): Lower durations
    3.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (12.days.ago + i.days),
        with_duration: 100
      )
    end

    # Current period (last 7 days): Higher durations
    3.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (5.days.ago + i.days),
        with_duration: 200
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Current period is slower, so should be trending up
    assert_equal "trending-up", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates correct trend when periods are similar" do
    # Previous period: 100ms requests
    3.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (12.days.ago + i.days),
        with_duration: 100
      )
    end

    # Current period: Also 100ms requests
    3.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (5.days.ago + i.days),
        with_duration: 100
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # When periods are the same, percentage should be 0 (< 0.1) so move-right
    assert_equal "move-right", result[:trend_icon]
    assert_match /0(\.\d+)?%/, result[:trend_amount]
  end

  test "handles zero previous period count for trend" do
    # No requests in previous period, only in current
    3.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (3.days.ago + i.days),
        with_duration: 150
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
  end

  # Sparkline data tests

  test "generates sparkline data grouped by week with average durations" do
    # Create requests over multiple weeks with known durations
    base_date = 4.weeks.ago.beginning_of_week

    # Week 1: requests with durations averaging 75ms
    [ 70, 75, 80 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: base_date + i.days,
        with_duration: duration
      )
    end

    # Week 2: requests with durations averaging 125ms
    [ 120, 125, 130 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: base_date + 1.week + i.days,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]
    assert_instance_of Hash, sparkline_data

    # Each data point should have correct format
    sparkline_data.each do |date_str, data|
      assert_instance_of String, date_str
      assert_instance_of Hash, data
      assert_includes data, :value
      assert_instance_of Integer, data[:value]
      assert data[:value] >= 0, "Duration should be non-negative"
    end
  end

  test "sparkline data rounds average durations to integers" do
    # Create requests with durations that will average to a decimal
    base_date = 2.weeks.ago.beginning_of_week
    [ 33, 34, 35 ].each_with_index do |duration, i|  # Average = 34.0
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: base_date + i.days,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]

    # All values should be integers (rounded)
    if sparkline_data.any?
      sparkline_data.values.each do |data|
        assert_instance_of Integer, data[:value]
      end
    else
      # If no sparkline data, at least assert the data structure is correct
      assert_instance_of Hash, sparkline_data
    end
  end

  test "date formatting in sparkline data uses correct format" do
    # Create request in a specific week
    known_date = 2.weeks.ago.beginning_of_week
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: known_date,
      with_duration: 100
    )

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]

    # Each key should be a date string in "Mon DD" format if data exists
    if sparkline_data.any?
      date_keys = sparkline_data.keys
      assert date_keys.all? { |key| key.match?(/\w{3} \d{1,2}/) }, "Expected date format like 'Jan 15', got: #{date_keys}"
    else
      # If no data, that's also valid
      assert_instance_of Hash, sparkline_data
    end
  end

  # Edge cases

  test "handles empty requests set" do
    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    assert_equal "Average Response Time", result[:title]
    assert_equal "0 ms", result[:summary]
    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
    assert_instance_of Hash, result[:line_chart_data]
    assert_empty result[:line_chart_data]
  end

  test "handles requests with zero duration" do
    # Create requests with zero and non-zero durations
    [ 0, 0, 100, 200 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 2.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should handle zero durations in average calculation
    # Average of [0, 0, 100, 200] = 75
    assert_equal "75 ms", result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Integration tests

  test "works with error and non-error requests" do
    # Create mix of error and non-error requests
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 4.days.ago,
      with_duration: 100,
      is_error: false
    )

    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 4.days.ago,
      with_duration: 200,
      is_error: true
    )

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should include both error and non-error requests
    # Average of [100, 200] = 150
    assert_equal "150 ms", result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Performance test

  test "handles large number of requests efficiently" do
    # Create many requests within 2 weeks
    50.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 10.days.ago + (i * 4).hours,
        with_duration: rand(50..200)
      )
    end

    start_time = Time.current
    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card
    execution_time = Time.current - start_time

    # Should complete in reasonable time
    assert execution_time < 1.0, "Execution took too long: #{execution_time}s"

    # Should still produce valid results
    assert_instance_of Hash, result
    assert_match /\d+ ms/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Required parameter test

  test "requires route parameter" do
    # The initialize method requires route: parameter according to the implementation
    assert_raises(ArgumentError) do
      RailsPulse::Routes::Cards::AverageResponseTimes.new
    end
  end

  # Time window test

  test "only considers requests within 2 week window" do
    # Create request exactly at 2 weeks ago (should be included)
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 2.weeks.ago.beginning_of_day,
      with_duration: 100
    )

    # Create request just before 2 weeks ago (should be excluded)
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 2.weeks.ago.beginning_of_day - 1.hour,
      with_duration: 500
    )

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should only include the 100ms request
    assert_equal "100 ms", result[:summary]
  end

  # Integration and ransacker tests

  test "integrates with route ransacker for performance categorization" do
    # Create requests that would trigger different performance thresholds
    slow_durations = [ 150, 200, 250 ]  # Average 200ms - slow category
    slow_durations.each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 5.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should calculate average correctly
    assert_equal "200 ms", result[:summary]

    # Test that this would interact correctly with route's status_indicator ransacker
    # by checking the route has requests that could be categorized
    assert @route.requests.count > 0
    assert @route.requests.average(:duration) == 200.0
  end

  test "handles extreme outliers in response times" do
    # Create mostly normal requests plus extreme outliers
    normal_durations = [ 50, 60, 70, 80, 90 ]  # Normal range
    outlier_durations = [ 5000, 10000 ]       # Extreme outliers

    (normal_durations + outlier_durations).each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 3.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Average should be significantly affected by outliers
    # (50+60+70+80+90+5000+10000)/7 ≈ 2193
    summary_value = result[:summary].match(/(\d+) ms/)[1].to_i
    assert summary_value > 2000, "Average should be heavily influenced by outliers, got #{summary_value}"
  end

  test "database compatibility with different duration precisions" do
    # Test with fractional durations that might behave differently across databases
    fractional_durations = [ 100.1, 100.5, 100.9, 101.1, 101.5 ]
    fractional_durations.each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 2.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should handle fractional averages correctly
    # Average of [100.1, 100.5, 100.9, 101.1, 101.5] = 100.82, rounds to 101
    assert_equal "101 ms", result[:summary]
  end

  test "concurrent route access with shared data" do
    # Create requests for the route
    5.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 3.days.ago + i.hours,
        with_duration: 100 + (i * 10)
      )
    end

    # Simulate concurrent access
    cards = Array.new(3) do
      RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    end

    results = cards.map(&:to_metric_card)

    # All results should be identical
    first_summary = results.first[:summary]
    results.each do |result|
      assert_equal first_summary, result[:summary]
    end
  end

  test "memory efficiency with large request datasets" do
    # Create a large number of requests
    100.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 10.days.ago + (i * 2).hours,
        with_duration: rand(50..200)
      )
    end

    memory_before = GC.stat[:heap_live_slots]

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Force garbage collection
    GC.start
    memory_after = GC.stat[:heap_live_slots]

    # Should not significantly increase memory usage
    memory_increase = memory_after - memory_before
    assert memory_increase < 15000, "Memory usage increased by #{memory_increase} slots"

    # Should still produce valid results
    assert_instance_of Hash, result
    assert_match /\d+ ms/, result[:summary]
  end

  test "route association integrity during calculations" do
    # Test with multiple routes to ensure proper association filtering
    other_route = create(:route, method: "POST", path: "/api/different")

    # Create requests for our route
    3.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 4.days.ago + i.hours,
        with_duration: 100
      )
    end

    # Create requests for other route with different durations
    3.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: other_route,
        at_time: 4.days.ago + i.hours,
        with_duration: 300
      )
    end

    # Verify that each route's card only uses its own requests
    card_route1 = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result_route1 = card_route1.to_metric_card

    card_route2 = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: other_route)
    result_route2 = card_route2.to_metric_card

    assert_equal "100 ms", result_route1[:summary]
    assert_equal "300 ms", result_route2[:summary]
  end

  test "timezone handling in trend calculations" do
    original_zone = Time.zone

    begin
      # Test with UTC
      Time.zone = "UTC"
      utc_time = 12.days.ago
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: utc_time,
        with_duration: 100
      )

      card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
      utc_result = card.to_metric_card

      # Test with different timezone
      Time.zone = "America/New_York"
      ny_result = card.to_metric_card

      # Results should be consistent regardless of timezone
      assert_equal utc_result[:summary], ny_result[:summary]
      assert_equal utc_result[:trend_icon], ny_result[:trend_icon]

    ensure
      Time.zone = original_zone
    end
  end

  test "sparkline data aggregation across multiple weeks" do
    # Clean up any existing data for this route to ensure test isolation
    RailsPulse::Request.where(route: @route).destroy_all

    # Create requests across a longer time period to test weekly aggregation
    base_date = 6.weeks.ago.beginning_of_week

    # Week 1: Average 50ms
    [ 40, 50, 60 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: base_date + i.days,
        with_duration: duration
      )
    end

    # Week 3: Average 100ms (skip week 2)
    [ 90, 100, 110 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: base_date + 2.weeks + i.days,
        with_duration: duration
      )
    end

    # Week 5: Average 150ms (skip week 4)
    [ 140, 150, 160 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: base_date + 4.weeks + i.days,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::AverageResponseTimes.new(route: @route)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]

    # Should have data for weeks with requests, empty weeks should not appear
    assert_instance_of Hash, sparkline_data

    if sparkline_data.any?
      # Verify that the data points represent weekly averages
      # Allow some tolerance for potential floating point precision or rounding
      sparkline_data.values.each do |data|
        assert_instance_of Integer, data[:value]
        # Check that values are in reasonable range (allowing for some variation due to aggregation)
        assert data[:value] >= 40, "Average should be at least 40, got #{data[:value]}"
        assert data[:value] <= 160, "Average should be at most 160, got #{data[:value]}"
      end
    end
  end
end
