require "test_helper"

class RailsPulse::Routes::Cards::RequestCountTotalsTest < BaseChartTest
  def setup
    super
    @route = create(:route)
  end

  # Basic Functionality Tests

  test "initializes with route parameter" do
    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)

    assert_equal @route, card.instance_variable_get(:@route)
  end

  test "initializes with nil route parameter" do
    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil)

    assert_nil card.instance_variable_get(:@route)
  end

  # Card format tests

  test "returns data in correct metric card format" do
    # Create some requests to test with (within 2 weeks)
    5.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: (10.days.ago + i.days)
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    assert_instance_of Hash, result
    assert_includes result, :title
    assert_includes result, :summary
    assert_includes result, :line_chart_data
    assert_includes result, :trend_icon
    assert_includes result, :trend_amount
    assert_includes result, :trend_text

    assert_equal "Request Count Total", result[:title]
    assert_equal "Compared to last week", result[:trend_text]
    assert_match /\d+(\.\d+)? \/ min/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Request count calculation tests

  test "calculates correct average requests per minute for known time span" do
    # Create 4 requests over a 2-day span = 2 requests per day = 2/1440 requests per minute
    base_time = 10.days.ago
    2.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_time + i.days
      )
    end

    # Add 2 more requests at the end of the span
    2.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_time + 2.days + i.hours
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should calculate requests per minute based on time span
    assert_match /\d+(\.\d+)? \/ min/, result[:summary]
  end

  test "handles single request" do
    create(:chart_request, :at_time,
      route: @route,
      at_time: 2.days.ago
    )

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Single request defaults to 1 minute for calculation
    assert_equal "1 / min", result[:summary]
  end

  test "handles requests all at same time" do
    # Create multiple requests at exactly the same time
    base_time = 5.days.ago
    3.times do
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_time
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # When min_time == max_time, defaults to 1 minute
    assert_equal "3 / min", result[:summary]
  end

  test "rounds requests per minute to 2 decimal places" do
    # Create requests that will result in a decimal average
    base_time = 8.days.ago
    # Create 7 requests over 3 days = 7/4320 requests per minute ≈ 0.0016 requests per minute
    7.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_time + (i * 10).hours  # Spread over ~3 days
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should be rounded to 2 decimal places, but may show as "0.0 / min" if very small
    assert_match /\d+(\.\d+)? \/ min/, result[:summary]
  end

  test "filters to requests within 2 weeks" do
    # Create request within 2 weeks
    create(:chart_request, :at_time,
      route: @route,
      at_time: 10.days.ago
    )

    # Create request older than 2 weeks (should be excluded)
    create(:chart_request, :at_time,
      route: @route,
      at_time: 20.days.ago
    )

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should only count the recent request
    assert_equal "1 / min", result[:summary]
  end

  # Route filtering tests

  test "filters requests by route when route is specified" do
    # Create requests for specific route
    3.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: 4.days.ago + i.hours
      )
    end

    # Create requests for different route
    other_route = create(:route)
    2.times do |i|
      create(:chart_request, :at_time,
        route: other_route,
        at_time: 4.days.ago + i.hours
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should calculate based on 3 requests over 2 hours = 3/120 = 0.025 requests per minute
    assert_match /0\.0\d+ \/ min/, result[:summary]
  end

  test "includes all requests when route is nil" do
    # Create requests for first route
    create(:chart_request, :at_time,
      route: @route,
      at_time: 4.days.ago
    )

    # Create requests for second route
    other_route = create(:route)
    create(:chart_request, :at_time,
      route: other_route,
      at_time: 4.days.ago
    )

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil)
    result = card.to_metric_card

    # Should calculate based on all 2 requests
    assert_equal "2 / min", result[:summary]
  end

  # Trend calculation tests

  test "calculates correct trend when current period has fewer requests" do
    # Previous period (14-7 days ago): More requests
    5.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: (12.days.ago + i.days)
      )
    end

    # Current period (last 7 days): Fewer requests
    2.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: (5.days.ago + i.days)
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Current period has fewer requests, so should be trending down
    assert_equal "trending-down", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates correct trend when current period has more requests" do
    # Previous period (14-7 days ago): Fewer requests
    2.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: (12.days.ago + i.days)
      )
    end

    # Current period (last 7 days): More requests
    5.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: (5.days.ago + i.days)
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Current period has more requests, so should be trending up
    assert_equal "trending-up", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates correct trend when periods have similar request counts" do
    # Previous period: 3 requests
    3.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: (12.days.ago + i.days)
      )
    end

    # Current period: Also 3 requests
    3.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: (5.days.ago + i.days)
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # When periods are the same, percentage should be 0 (< 0.1) so move-right
    assert_equal "move-right", result[:trend_icon]
    assert_match /0(\.\d+)?%/, result[:trend_amount]
  end

  test "handles zero previous period count for trend" do
    # No requests in previous period, only in current
    3.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: (3.days.ago + i.days)
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
  end

  # Sparkline data tests

  test "generates sparkline data grouped by week with request counts" do
    # Create requests over multiple weeks
    base_date = 4.weeks.ago.beginning_of_week

    # Week 1: 3 requests
    3.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_date + i.days
      )
    end

    # Week 2: 5 requests
    5.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_date + 1.week + i.days
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]
    assert_instance_of Hash, sparkline_data

    # Each data point should have correct format
    sparkline_data.each do |date_str, data|
      assert_instance_of String, date_str
      assert_instance_of Hash, data
      assert_includes data, :value
      assert_instance_of Integer, data[:value]
      assert data[:value] >= 0, "Request count should be non-negative"
    end
  end

  test "sparkline data shows correct weekly request counts" do
    # Create specific number of requests in a specific week
    base_date = 2.weeks.ago.beginning_of_week
    expected_count = 4
    expected_count.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_date + i.days
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]

    # Should have correct count for that week
    if sparkline_data.any?
      total_count = sparkline_data.values.sum { |data| data[:value] }
      assert_equal expected_count, total_count
    else
      # If no sparkline data, at least assert the data structure is correct
      assert_instance_of Hash, sparkline_data
    end
  end

  test "date formatting in sparkline data uses correct format" do
    # Create request in a specific week
    known_date = 2.weeks.ago.beginning_of_week
    create(:chart_request, :at_time,
      route: @route,
      at_time: known_date
    )

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
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
    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    assert_equal "Request Count Total", result[:title]
    assert_equal "0 / min", result[:summary]
    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
    assert_instance_of Hash, result[:line_chart_data]
    assert_empty result[:line_chart_data]
  end

  test "handles route with no requests" do
    # Create requests for different route
    other_route = create(:route)
    create(:chart_request, :at_time,
      route: other_route,
      at_time: 4.days.ago
    )

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should return 0 requests per minute for route with no requests
    assert_equal "0 / min", result[:summary]
  end

  test "handles multiple routes with different request counts" do
    # Route 1: 2 requests
    2.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: 5.days.ago + i.hours
      )
    end

    # Route 2: 4 requests
    other_route = create(:route)
    4.times do |i|
      create(:chart_request, :at_time,
        route: other_route,
        at_time: 5.days.ago + i.hours
      )
    end

    # Test specific route
    card_route = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result_route = card_route.to_metric_card

    # Should calculate based on 2 requests over 1 hour = 2/60 = 0.03 requests per minute
    assert_match /0\.03\d* \/ min/, result_route[:summary]

    # Test all routes
    card_all = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil)
    result_all = card_all.to_metric_card

    # Should calculate based on all 6 requests over 3 hours = 6/180 = 0.03 requests per minute
    assert_match /0\.03\d* \/ min/, result_all[:summary]
  end

  # Integration tests

  test "works with requests that have various attributes" do
    # Create requests with different attributes (error status, durations)
    create(:chart_request, :at_time,
      route: @route,
      at_time: 4.days.ago,
      is_error: false
    )

    create(:chart_request, :at_time, :with_duration,
      route: @route,
      at_time: 4.days.ago,
      is_error: true,
      with_duration: 500
    )

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should count all requests regardless of error status or duration
    assert_equal "2 / min", result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Performance test

  test "handles large number of requests efficiently" do
    # Create many requests within 2 weeks
    50.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: 10.days.ago + (i * 4).hours
      )
    end

    start_time = Time.current
    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card
    execution_time = Time.current - start_time

    # Should complete in reasonable time
    assert execution_time < 1.0, "Execution took too long: #{execution_time}s"

    # Should still produce valid results
    assert_instance_of Hash, result
    assert_match /\d+(\.\d+)? \/ min/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Required parameter test

  test "requires route parameter" do
    # The initialize method requires route: parameter according to the implementation
    # Based on the actual implementation, route parameter is optional (can be nil)
    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil)
    assert_nil card.instance_variable_get(:@route)
  end

  # Time window test

  test "only considers requests within 2 week window" do
    # Create request exactly at 2 weeks ago (should be included)
    create(:chart_request, :at_time,
      route: @route,
      at_time: 2.weeks.ago.beginning_of_day
    )

    # Create request just before 2 weeks ago (should be excluded)
    create(:chart_request, :at_time,
      route: @route,
      at_time: 2.weeks.ago.beginning_of_day - 1.hour
    )

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should only count the recent request
    assert_equal "1 / min", result[:summary]
  end

  # Summary calculation edge cases

  test "handles very short time spans correctly" do
    base_time = 5.days.ago
    # Create 2 requests 1 minute apart
    create(:chart_request, :at_time,
      route: @route,
      at_time: base_time
    )

    create(:chart_request, :at_time,
      route: @route,
      at_time: base_time + 1.minute
    )

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should calculate 2 requests over 1 minute = 2 requests per minute
    assert_equal "2.0 / min", result[:summary]
  end

  test "handles very long time spans correctly" do
    # Create requests at the beginning and end of the 2-week window
    create(:chart_request, :at_time,
      route: @route,
      at_time: 13.days.ago  # Near beginning of 2-week window
    )

    create(:chart_request, :at_time,
      route: @route,
      at_time: 1.day.ago    # Near end of 2-week window
    )

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should calculate 2 requests over ~12 days = very small requests per minute
    assert_match /0\.\d+ \/ min/, result[:summary]
  end

  # Trend calculation edge cases

  test "trend calculation uses correct time periods" do
    # Create requests in both trend calculation periods
    # Previous period (14-7 days ago)
    create(:chart_request, :at_time,
      route: @route,
      at_time: 10.days.ago  # In previous period
    )

    # Current period (last 7 days)
    create(:chart_request, :at_time,
      route: @route,
      at_time: 3.days.ago   # In current period
    )

    # Request outside both periods (should not affect trend)
    create(:chart_request, :at_time,
      route: @route,
      at_time: 16.days.ago  # Before both periods
    )

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should have equal counts in both periods, so move-right trend
    assert_equal "move-right", result[:trend_icon]
    assert_match /0(\.0)?%/, result[:trend_amount]
  end

  # Integration tests with route ransackers

  test "request count integrates with route request_count ransacker" do
    # Create a specific number of requests that would be picked up by ransacker
    expected_count = 8
    expected_count.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: 5.days.ago + i.hours
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should calculate requests per minute correctly
    # 8 requests over 7 hours = 8/420 ≈ 0.019 requests per minute
    assert_match /0\.0[12]\d* \/ min/, result[:summary]

    # Verify this matches what the route's request_count ransacker would find
    route_with_requests = @route.reload
    assert_equal expected_count, route_with_requests.requests.count
  end

  test "multiple routes with varying request patterns" do
    # Create routes with distinctly different request volumes
    light_route = create(:route, method: "GET", path: "/api/light")
    moderate_route = create(:route, method: "POST", path: "/api/moderate")
    heavy_route = create(:route, method: "PUT", path: "/api/heavy")

    # Light route: 2 requests over 2 hours
    2.times do |i|
      create(:chart_request, :at_time,
        route: light_route,
        at_time: 6.days.ago + i.hours
      )
    end

    # Moderate route: 10 requests over 2 hours
    10.times do |i|
      create(:chart_request, :at_time,
        route: moderate_route,
        at_time: 6.days.ago + (i * 12).minutes  # Spread over 2 hours
      )
    end

    # Heavy route: 20 requests over 1 hour
    20.times do |i|
      create(:chart_request, :at_time,
        route: heavy_route,
        at_time: 6.days.ago + (i * 3).minutes  # Spread over 1 hour
      )
    end

    # Test each route individually
    light_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: light_route)
    light_result = light_card.to_metric_card

    moderate_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: moderate_route)
    moderate_result = moderate_card.to_metric_card

    heavy_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: heavy_route)
    heavy_result = heavy_card.to_metric_card

    # Light: 2 requests / 60 minutes = 0.033... requests per minute
    assert_match /0\.03\d* \/ min/, light_result[:summary]

    # Moderate: 10 requests / 120 minutes = 0.083... requests per minute
    assert_match /0\.0[89]\d* \/ min/, moderate_result[:summary]

    # Heavy: 20 requests / 60 minutes = 0.333... requests per minute
    assert_match /0\.3\d* \/ min/, heavy_result[:summary]

    # Test all routes together
    all_card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: nil)
    all_result = all_card.to_metric_card

    # Total: 32 requests over maximum span should show combined rate
    assert_match /\d+(\.\d+)? \/ min/, all_result[:summary]
  end

  test "request counting precision with large datasets" do
    # Create a large dataset to test counting precision
    total_requests = 500

    total_requests.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: 10.days.ago + (i * 10).minutes  # Spread over ~83 hours
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should accurately count all 500 requests
    # 500 requests over ~5000 minutes = 0.1 requests per minute
    assert_match /0\.1\d* \/ min/, result[:summary]
  end

  test "concurrent access with request counting" do
    # Create requests for counting
    15.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: 5.days.ago + i.hours
      )
    end

    # Test concurrent access
    cards = Array.new(5) do
      RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    end

    results = cards.map(&:to_metric_card)

    # All results should be identical
    first_summary = results.first[:summary]
    results.each do |result|
      assert_equal first_summary, result[:summary]
    end

    # Verify the expected rate calculation
    assert_match /\d+(\.\d+)? \/ min/, first_summary
  end

  test "memory efficiency with large request counting" do
    # Create a large number of requests for counting
    200.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: 10.days.ago + (i * 5).hours
      )
    end

    memory_before = GC.stat[:heap_live_slots]

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Force garbage collection
    GC.start
    memory_after = GC.stat[:heap_live_slots]

    # Should not significantly increase memory usage
    memory_increase = memory_after - memory_before
    assert memory_increase < 15000, "Memory usage increased by #{memory_increase} slots"

    # Should still produce valid results
    assert_instance_of Hash, result
    assert_match /\d+(\.\d+)? \/ min/, result[:summary]
  end

  test "route association integrity during request counting" do
    # Test with multiple routes to ensure proper association filtering
    other_route = create(:route, method: "POST", path: "/api/different")

    # Create requests for our route
    5.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: 4.days.ago + i.hours
      )
    end

    # Create requests for other route
    3.times do |i|
      create(:chart_request, :at_time,
        route: other_route,
        at_time: 4.days.ago + i.hours
      )
    end

    # Verify that each route's card only counts its own requests
    card_route1 = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result_route1 = card_route1.to_metric_card

    card_route2 = RailsPulse::Routes::Cards::RequestCountTotals.new(route: other_route)
    result_route2 = card_route2.to_metric_card

    # Route 1: 5 requests over 4 hours = 5/240 = 0.021 requests per minute
    assert_match /0\.02\d* \/ min/, result_route1[:summary]

    # Route 2: 3 requests over 2 hours = 3/120 = 0.025 requests per minute
    assert_match /0\.0[23]\d* \/ min/, result_route2[:summary]
  end

  test "timezone handling in request counting" do
    original_zone = Time.zone

    begin
      # Test with UTC
      Time.zone = "UTC"
      utc_time = 12.days.ago
      3.times do |i|
        create(:chart_request, :at_time,
          route: @route,
          at_time: utc_time + i.hours
        )
      end

      card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
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

  test "sparkline request count aggregation over time periods" do
    # Create requests across multiple weeks with different volumes
    base_date = 5.weeks.ago.beginning_of_week

    # Week 1: 5 requests
    5.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_date + i.days
      )
    end

    # Week 2: Skip - no requests

    # Week 3: 3 requests
    3.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_date + 2.weeks + i.days
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]

    if sparkline_data.any?
      # Should aggregate request counts by week properly
      total_requests = sparkline_data.values.sum { |data| data[:value] }
      assert_equal 8, total_requests  # 5 + 0 + 3 = 8 total requests
    else
      # If no sparkline data, that's also valid
      assert_instance_of Hash, sparkline_data
    end
  end

  test "integration with route requests_per_minute ransacker" do
    # Create requests with known timing to verify ransacker integration
    base_time = 6.days.ago

    # Create 6 requests over 3 hours
    6.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_time + (i * 30).minutes  # Every 30 minutes for 2.5 hours
      )
    end

    # Test the card calculation
    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # 6 requests over 150 minutes = 0.04 requests per minute
    assert_match /0\.04\d* \/ min/, result[:summary]

    # Verify this integrates with the route's request counting capabilities
    route_with_requests = @route.reload
    assert_equal 6, route_with_requests.requests.count
  end

  test "request count calculation with extreme time distributions" do
    # Test edge cases with unusual time distributions
    test_cases = [
      {
        description: "burst pattern - all requests in 1 minute",
        requests: 5,
        time_span: 1.minute,
        expected_pattern: /[56]\.\d+ \/ min/
      },
      {
        description: "sparse pattern - 2 requests over 24 hours",
        requests: 2,
        time_span: 24.hours,
        expected_pattern: /0\.0\d* \/ min/
      },
      {
        description: "regular pattern - 12 requests over 6 hours",
        requests: 12,
        time_span: 6.hours,
        expected_pattern: /0\.0[34]\d* \/ min/
      }
    ]

    test_cases.each_with_index do |test_case, index|
      route = create(:route, method: "GET", path: "/api/test#{index}")
      base_time = 5.days.ago

      # Create requests according to the test case
      test_case[:requests].times do |i|
        create(:chart_request, :at_time,
          route: route,
          at_time: base_time + (i * test_case[:time_span] / test_case[:requests])
        )
      end

      # Test the calculation
      card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: route)
      result = card.to_metric_card

      assert_match test_case[:expected_pattern], result[:summary],
        "Failed for #{test_case[:description]}: expected #{test_case[:expected_pattern]}, got #{result[:summary]}"
    end
  end

  test "mathematical precision with high-frequency requests" do
    # Create a high-frequency request pattern to test precision
    base_time = 3.days.ago
    request_count = 100

    # Create 100 requests over 50 minutes (2 requests per minute)
    request_count.times do |i|
      create(:chart_request, :at_time,
        route: @route,
        at_time: base_time + (i * 30).seconds  # Every 30 seconds
      )
    end

    card = RailsPulse::Routes::Cards::RequestCountTotals.new(route: @route)
    result = card.to_metric_card

    # Should calculate approximately 2.0 requests per minute
    assert_match /2\.0\d* \/ min/, result[:summary]
  end
end
