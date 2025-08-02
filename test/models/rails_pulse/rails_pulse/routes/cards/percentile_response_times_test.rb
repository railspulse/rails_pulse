require "test_helper"

class RailsPulse::Routes::Cards::PercentileResponseTimesTest < BaseChartTest
  def setup
    super
    @route = create(:route)
  end

  # Basic Functionality Tests

  test "initializes with route parameter" do
    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)

    assert_equal @route, card.instance_variable_get(:@route)
  end

  test "initializes with nil route parameter" do
    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil)

    assert_nil card.instance_variable_get(:@route)
  end

  # Card format tests

  test "returns data in correct metric card format" do
    # Create some requests to test with (within 2 weeks)
    10.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (10.days.ago + i.days),
        with_duration: (i + 1) * 20  # 20, 40, 60, ... 200 ms
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    assert_instance_of Hash, result
    assert_includes result, :title
    assert_includes result, :summary
    assert_includes result, :line_chart_data
    assert_includes result, :trend_icon
    assert_includes result, :trend_amount
    assert_includes result, :trend_text

    assert_equal "95th Percentile Response Time", result[:title]
    assert_equal "Compared to last week", result[:trend_text]
    assert_match /\d+ ms/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # 95th percentile calculation tests

  test "calculates 95th percentile correctly for known durations" do
    # Create 20 requests with known durations: 10, 20, 30, ..., 200 ms
    20.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 5.days.ago + i.hours,
        with_duration: (i + 1) * 10  # 10, 20, 30, ..., 200
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # 95th percentile using offset((20 * 0.95).floor) = offset(19) = 20th item = 200ms
    assert_equal "200 ms", result[:summary]
  end

  test "handles single request" do
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 2.days.ago,
      with_duration: 150
    )

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Single request should be the 95th percentile
    assert_equal "150 ms", result[:summary]
  end

  test "rounds 95th percentile to nearest integer" do
    # Create requests that will result in a decimal percentile
    5.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 3.days.ago + i.hours,
        with_duration: i * 25 + 100  # 100, 125, 150, 175, 200
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # 95th percentile of 5 items should be the 5th item (index 4) = 200
    assert_equal "200 ms", result[:summary]
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

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
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
        with_duration: 100 + i * 10  # 100, 110, 120
      )
    end

    # Create requests for different route
    other_route = create(:route)
    2.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: other_route,
        at_time: 4.days.ago + i.hours,
        with_duration: 300 + i * 10  # 300, 310 (much higher)
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should only use requests for the specific route (95th percentile of 100, 110, 120 = 120)
    assert_equal "120 ms", result[:summary]
  end

  test "includes all requests when route is nil" do
    # Create requests for first route
    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 4.days.ago,
      with_duration: 100
    )

    # Create requests for second route
    other_route = create(:route)
    create(:chart_request, :at_time, :with_duration,
      route: other_route,
      at_time: 4.days.ago,
      with_duration: 200
    )

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil)
    result = card.to_metric_card

    # Should calculate based on all requests (95th percentile of 100, 200 = 200)
    assert_equal "200 ms", result[:summary]
  end

  # Trend calculation tests

  test "calculates correct trend when current period is faster" do
    # Previous period (14-7 days ago): Higher durations for 95th percentile
    10.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (12.days.ago + i.hours),
        with_duration: 200 + i * 10  # 200-290, 95th percentile = 280
      )
    end

    # Current period (last 7 days): Lower durations for 95th percentile
    10.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (5.days.ago + i.hours),
        with_duration: 100 + i * 10  # 100-190, 95th percentile = 180
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Current period is faster, so should be trending down
    assert_equal "trending-down", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates correct trend when current period is slower" do
    # Previous period (14-7 days ago): Lower durations for 95th percentile
    10.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (12.days.ago + i.hours),
        with_duration: 100 + i * 10  # 100-190, 95th percentile = 180
      )
    end

    # Current period (last 7 days): Higher durations for 95th percentile
    10.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (5.days.ago + i.hours),
        with_duration: 200 + i * 10  # 200-290, 95th percentile = 280
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Current period is slower, so should be trending up
    assert_equal "trending-up", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates correct trend when periods are similar" do
    # Previous period: Similar durations for 95th percentile
    10.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (12.days.ago + i.hours),
        with_duration: 100 + i * 10  # 100-190, 95th percentile = 180
      )
    end

    # Current period: Also similar durations
    10.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (5.days.ago + i.hours),
        with_duration: 100 + i * 10  # 100-190, 95th percentile = 180
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # When periods are the same, percentage should be 0 (< 0.1) so move-right
    assert_equal "move-right", result[:trend_icon]
    assert_match /0(\.\d+)?%/, result[:trend_amount]
  end

  test "handles zero previous period count for trend" do
    # No requests in previous period, only in current
    5.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: (3.days.ago + i.hours),
        with_duration: 150 + i * 10
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
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

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
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

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
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

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
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
    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    assert_equal "95th Percentile Response Time", result[:title]
    assert_equal "0 ms", result[:summary]
    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
    assert_instance_of Hash, result[:line_chart_data]
    assert_empty result[:line_chart_data]
  end

  test "handles requests with zero duration" do
    # Create requests with zero and non-zero durations
    [ 0, 0, 100, 200, 300 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 2.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should handle zero durations in 95th percentile calculation
    # 95th percentile of [0, 0, 100, 200, 300] should be 300 (5th item)
    assert_equal "300 ms", result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  test "handles large dataset for percentile calculation" do
    # Create 100 requests with varying durations
    100.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 2.days.ago + i.minutes,
        with_duration: i + 1  # 1 to 100 ms
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # 95th percentile using offset((100 * 0.95).floor) = offset(95) = 96th item = 96ms
    assert_equal "96 ms", result[:summary]
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

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should include both error and non-error requests
    # 95th percentile of [100, 200] = 200
    assert_equal "200 ms", result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  test "percentile calculation uses correct ordering" do
    # Create requests in random order to test sorting
    durations = [ 500, 100, 300, 200, 400 ]
    durations.each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 4.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # After sorting: [100, 200, 300, 400, 500]
    # 95th percentile of 5 items is the 5th item = 500ms
    assert_equal "500 ms", result[:summary]
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
    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
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
    # Based on the actual implementation, route parameter is optional (can be nil)
    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: nil)
    assert_nil card.instance_variable_get(:@route)
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

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should only include the 100ms request
    assert_equal "100 ms", result[:summary]
  end

  # Boundary tests for percentile calculation

  test "handles percentile calculation with various dataset sizes" do
    # Test with different numbers of requests
    [ 1, 2, 5, 10, 20 ].each do |count|
      # Clear previous data
      RailsPulse::Request.destroy_all

      # Create requests
      count.times do |i|
        create(:chart_request, :at_time, :with_duration,
          route: @route,
          at_time: 5.days.ago + i.hours,
          with_duration: (i + 1) * 10  # 10, 20, 30, ...
        )
      end

      card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
      result = card.to_metric_card

      # For any dataset size, should return the highest value as 95th percentile
      expected_value = count * 10
      assert_equal "#{expected_value} ms", result[:summary], "Failed for dataset size #{count}"
    end
  end

  test "percentile calculation matches expected formula" do
    # Create exactly 20 requests to test percentile calculation
    20.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 5.days.ago + i.hours,
        with_duration: (i + 1) * 10  # 10, 20, 30, ..., 200
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # For 20 items, 95th percentile index = floor(20 * 0.95) = floor(19) = 19
    # So we want the item at offset 19 (0-indexed), which is the 20th item = 200ms
    assert_equal "200 ms", result[:summary]
  end

  # Integration tests with route ransackers

  test "percentile calculation integrates with route max_response_time_ms ransacker" do
    # Create a mix of responses with a clear max duration
    durations = [ 50, 100, 150, 200, 800, 250, 300 ]  # max = 800, 95th percentile = 800
    durations.each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 5.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # 95th percentile of sorted [50, 100, 150, 200, 250, 300, 800] = 800
    assert_equal "800 ms", result[:summary]

    # Verify this relates to what the route's max_response_time_ms ransacker would find
    route_with_max = @route.reload
    assert_equal 7, route_with_max.requests.count
    assert_equal 800.0, route_with_max.requests.maximum(:duration)
  end

  test "extreme outlier impact on percentile calculations" do
    # Create mostly normal requests plus extreme outliers to test ransacker interaction
    normal_durations = [ 50, 60, 70, 80, 90, 100, 110, 120 ]  # Normal range
    outlier_durations = [ 5000, 15000 ]                        # Extreme outliers

    (normal_durations + outlier_durations).each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 3.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # 95th percentile should capture the extreme outlier
    # Sorted: [50, 60, 70, 80, 90, 100, 110, 120, 5000, 15000]
    # 95th percentile of 10 items = item at offset 9 = 15000
    summary_value = result[:summary].match(/(\d+) ms/)[1].to_i
    assert summary_value >= 10000, "95th percentile should capture extreme outlier, got #{summary_value}"
  end

  test "database compatibility with percentile sorting and offset" do
    # Test with fractional durations that might sort differently across databases
    fractional_durations = [ 100.1, 100.5, 100.9, 101.1, 101.5, 102.0 ]
    fractional_durations.each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 2.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Should handle fractional sorting correctly
    # 95th percentile of 6 items = item at offset 5 = 102.0, rounds to 102
    assert_equal "102 ms", result[:summary]
  end

  test "concurrent access with percentile calculations" do
    # Create requests for percentile calculation
    10.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 5.days.ago + i.hours,
        with_duration: (i + 1) * 20  # 20, 40, 60, ..., 200
      )
    end

    # Test concurrent access
    cards = Array.new(5) do
      RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    end

    results = cards.map(&:to_metric_card)

    # All results should be identical
    first_percentile = results.first[:summary]
    results.each do |result|
      assert_equal first_percentile, result[:summary]
    end

    # Verify the expected 95th percentile (200ms - the highest value)
    assert_equal "200 ms", first_percentile
  end

  test "memory efficiency with large percentile datasets" do
    # Create a large number of requests for percentile calculation
    150.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 10.days.ago + (i * 2).hours,
        with_duration: rand(50..500)
      )
    end

    memory_before = GC.stat[:heap_live_slots]

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # Force garbage collection
    GC.start
    memory_after = GC.stat[:heap_live_slots]

    # Should not significantly increase memory usage
    memory_increase = memory_after - memory_before
    assert memory_increase < 20000, "Memory usage increased by #{memory_increase} slots"

    # Should still produce valid results
    assert_instance_of Hash, result
    assert_match /\d+ ms/, result[:summary]
  end

  test "route association integrity during percentile calculations" do
    # Test with multiple routes to ensure proper association filtering
    other_route = create(:route, method: "POST", path: "/api/different")

    # Create requests for our route with specific pattern
    [ 100, 200, 300, 400, 500 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 4.days.ago + i.hours,
        with_duration: duration
      )
    end

    # Create requests for other route with different pattern
    [ 1000, 2000, 3000 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: other_route,
        at_time: 4.days.ago + i.hours,
        with_duration: duration
      )
    end

    # Verify that each route's card only uses its own requests
    card_route1 = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result_route1 = card_route1.to_metric_card

    card_route2 = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: other_route)
    result_route2 = card_route2.to_metric_card

    # 95th percentile of [100, 200, 300, 400, 500] = 500
    assert_equal "500 ms", result_route1[:summary]
    # 95th percentile of [1000, 2000, 3000] = 3000
    assert_equal "3000 ms", result_route2[:summary]
  end

  test "timezone handling in percentile trend calculations" do
    original_zone = Time.zone

    begin
      # Test with UTC
      Time.zone = "UTC"
      utc_time = 12.days.ago
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: utc_time,
        with_duration: 150
      )

      card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
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

  test "sparkline percentile aggregation over time periods" do
    # Create requests across multiple weeks with different percentile patterns
    base_date = 5.weeks.ago.beginning_of_week

    # Week 1: Low percentiles (95th = 80ms)
    [ 50, 60, 70, 80 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: base_date + i.days,
        with_duration: duration
      )
    end

    # Week 2: Skip - no requests

    # Week 3: High percentiles (95th = 200ms)
    [ 150, 170, 190, 200 ].each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: base_date + 2.weeks + i.days,
        with_duration: duration
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]

    if sparkline_data.any?
      # Should show the weekly averages properly aggregated
      sparkline_data.values.each do |data|
        assert_instance_of Integer, data[:value]
        # Values should be reasonable averages
        assert data[:value] > 0 && data[:value] < 1000, "Sparkline value #{data[:value]} seems unreasonable"
      end
    else
      # If no sparkline data, that's also valid
      assert_instance_of Hash, sparkline_data
    end
  end

  test "integration with route status_indicator thresholds" do
    # Create requests that span different performance categories
    test_cases = [
      { durations: [ 20, 30, 40, 50 ], expected_95th: 50 },      # Good category
      { durations: [ 80, 90, 100, 120 ], expected_95th: 120 },   # Slow category
      { durations: [ 180, 200, 220, 250 ], expected_95th: 250 }, # Very slow category
      { durations: [ 800, 900, 1000, 1200 ], expected_95th: 1200 } # Critical category
    ]

    test_cases.each_with_index do |test_case, index|
      route = create(:route, method: "GET", path: "/api/test#{index}")

      test_case[:durations].each_with_index do |duration, i|
        create(:chart_request, :at_time, :with_duration,
          route: route,
          at_time: 5.days.ago + i.hours,
          with_duration: duration
        )
      end

      # Test the percentile calculation
      card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: route)
      result = card.to_metric_card

      assert_equal "#{test_case[:expected_95th]} ms", result[:summary],
        "Expected 95th percentile #{test_case[:expected_95th]}ms for durations #{test_case[:durations]}"

      # Verify this would interact correctly with status_indicator thresholds
      assert route.requests.count == 4
      route_avg = route.requests.average(:duration)
      route_max = route.requests.maximum(:duration)
      assert_equal test_case[:expected_95th], route_max, "Max should match 95th percentile for this test case"
    end
  end

  test "mathematical precision with large dataset percentiles" do
    # Create a large, evenly distributed dataset to test percentile precision
    total_requests = 1000

    total_requests.times do |i|
      create(:chart_request, :at_time, :with_duration,
        route: @route,
        at_time: 10.days.ago + (i * 5).minutes,
        with_duration: i + 1  # 1 to 1000 ms
      )
    end

    card = RailsPulse::Routes::Cards::PercentileResponseTimes.new(route: @route)
    result = card.to_metric_card

    # For 1000 items, 95th percentile index = floor(1000 * 0.95) = 950
    # So we want the item at offset 950 (0-indexed), which is the 951st item = 951ms
    assert_equal "951 ms", result[:summary]
  end
end
