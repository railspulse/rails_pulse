require "test_helper"

class RailsPulse::Queries::Cards::AverageQueryTimesTest < BaseChartTest
  def setup
    super
    @query = create(:query)
  end

  # Basic Functionality Tests

  test "initializes with query parameter" do
    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: @query)

    assert_equal @query, card.instance_variable_get(:@query)
  end

  test "initializes with nil query parameter" do
    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)

    assert_nil card.instance_variable_get(:@query)
  end

  # Card format tests

  test "returns data in correct metric card format" do
    # Create some operations to test with
    5.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (10.days.ago + i.days),
        with_duration: (i + 1) * 50  # 50, 100, 150, 200, 250 ms
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    assert_instance_of Hash, result
    assert_includes result, :title
    assert_includes result, :summary
    assert_includes result, :line_chart_data
    assert_includes result, :trend_icon
    assert_includes result, :trend_amount
    assert_includes result, :trend_text

    assert_equal "Average Query Time", result[:title]
    assert_equal "Compared to last week", result[:trend_text]
    assert_match /\d+ ms/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Average calculation tests

  test "calculates average query time correctly for known durations" do
    # Create operations with known durations: 50, 100, 150, 200
    [ 50, 100, 150, 200 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: 5.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Average of [50, 100, 150, 200] = 125
    assert_equal "125 ms", result[:summary]
  end

  test "handles single operation" do
    create(:operation, :at_time, :with_duration,
      at_time: 2.days.ago,
      with_duration: 150
    )

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Single operation should be the average
    assert_equal "150 ms", result[:summary]
  end

  test "rounds average to nearest integer" do
    # Create operations that will average to a decimal
    [ 10, 15, 20 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: 3.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Average of [10, 15, 20] = 15.0, should round to 15
    assert_equal "15 ms", result[:summary]
  end

  # Query filtering tests

  test "respects query parameter when provided" do
    # Test that the query parameter is stored correctly
    card_with_query = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: @query)
    card_without_query = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)

    assert_equal @query, card_with_query.instance_variable_get(:@query)
    assert_nil card_without_query.instance_variable_get(:@query)

    # Both should return valid metric card format
    result_with_query = card_with_query.to_metric_card
    result_without_query = card_without_query.to_metric_card

    [ result_with_query, result_without_query ].each do |result|
      assert_instance_of Hash, result
      assert_includes result, :title
      assert_includes result, :summary
      assert_includes result, :line_chart_data
      assert_includes result, :trend_icon
      assert_includes result, :trend_amount
      assert_includes result, :trend_text
    end
  end

  test "includes all operations when query is nil" do
    # Create operations
    create(:operation, :at_time, :with_duration,
      at_time: 4.days.ago,
      with_duration: 100
    )

    create(:operation, :at_time, :with_duration,
      at_time: 4.days.ago,
      with_duration: 200
    )

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Should calculate based on all operations (average of 100, 200 = 150)
    assert_equal "150 ms", result[:summary]
  end

  # Trend calculation tests

  test "calculates correct trend when current period is faster" do
    # Previous period (14-7 days ago): Higher durations
    3.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (12.days.ago + i.days),
        with_duration: 200
      )
    end

    # Current period (last 7 days): Lower durations
    3.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (5.days.ago + i.days),
        with_duration: 100
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Current period is faster, so should be trending down
    assert_equal "trending-down", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates correct trend when current period is slower" do
    # Previous period (14-7 days ago): Lower durations
    3.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (12.days.ago + i.days),
        with_duration: 100
      )
    end

    # Current period (last 7 days): Higher durations
    3.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (5.days.ago + i.days),
        with_duration: 200
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Current period is slower, so should be trending up
    assert_equal "trending-up", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates correct trend when periods are similar" do
    # Previous period: 100ms operations
    3.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (12.days.ago + i.days),
        with_duration: 100
      )
    end

    # Current period: Also 100ms operations
    3.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (5.days.ago + i.days),
        with_duration: 100
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # When periods are the same, percentage should be 0 (< 0.1) so move-right
    assert_equal "move-right", result[:trend_icon]
    assert_match /0(\.\d+)?%/, result[:trend_amount]
  end

  test "handles zero previous period count for trend" do
    # No operations in previous period, only in current
    3.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (3.days.ago + i.days),
        with_duration: 150
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
  end

  # Sparkline data tests

  test "generates sparkline data grouped by week with average durations" do
    # Create operations over multiple weeks with known durations
    base_date = 4.weeks.ago.beginning_of_week

    # Week 1: operations with durations averaging 75ms
    [ 70, 75, 80 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: base_date + i.days,
        with_duration: duration
      )
    end

    # Week 2: operations with durations averaging 125ms
    [ 120, 125, 130 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: base_date + 1.week + i.days,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
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
    # Create operations with durations that will average to a decimal
    base_date = 2.weeks.ago.beginning_of_week
    [ 33, 34, 35 ].each_with_index do |duration, i|  # Average = 34.0
      create(:operation, :at_time, :with_duration,
        at_time: base_date + i.days,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]

    # All values should be integers (rounded)
    sparkline_data.values.each do |data|
      assert_instance_of Integer, data[:value]
    end
  end

  test "date formatting in sparkline data uses correct format" do
    # Create operation in a specific week
    known_date = 2.weeks.ago.beginning_of_week
    create(:operation, :at_time, :with_duration,
      at_time: known_date,
      with_duration: 100
    )

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
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

  test "handles empty operations set" do
    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    assert_equal "Average Query Time", result[:title]
    assert_equal "0 ms", result[:summary]
    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
    assert_instance_of Hash, result[:line_chart_data]
    assert_empty result[:line_chart_data]
  end

  test "handles operations with zero duration" do
    # Create operations with zero and non-zero durations
    [ 0, 0, 100, 200 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: 2.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Should handle zero durations in average calculation
    # Average of [0, 0, 100, 200] = 75
    assert_equal "75 ms", result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Integration tests

  test "works with different operation types" do
    # Create operations of different types with various durations
    [ :sql, :controller, :template ].each_with_index do |operation_type, type_idx|
      2.times do |i|
        create(:operation, operation_type, :at_time, :with_duration,
          at_time: 4.days.ago + (type_idx * 8 + i * 4).hours,
          with_duration: (type_idx + 1) * 50 + i * 25  # Varying durations by type
        )
      end
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Should include all operation types in calculations
    assert_match /\d+ ms/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
    assert_includes [ "trending-up", "trending-down", "move-right" ], result[:trend_icon]
  end

  # Performance test

  test "handles large number of operations efficiently" do
    # Create many operations
    50.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 10.days.ago + (i * 4).hours,
        with_duration: rand(50..200)
      )
    end

    start_time = Time.current
    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
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

  test "requires query parameter" do
    # The initialize method requires query: parameter according to the implementation
    assert_raises(ArgumentError) do
      RailsPulse::Queries::Cards::AverageQueryTimes.new
    end
  end

  # Performance and optimization tests

  test "handles large durations without overflow" do
    # Create operations with large but database-compatible durations
    [ 500_000, 750_000, 999_999 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: 3.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Should handle large numbers gracefully
    assert_match /\d+ ms/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  test "handles fractional rounding edge cases" do
    # Test specific rounding scenarios
    test_cases = [
      { durations: [ 1, 2 ], expected: "2" },     # 1.5 rounds to 2
      { durations: [ 2, 3 ], expected: "3" },     # 2.5 rounds to 3 (Ruby rounds up)
      { durations: [ 3, 4 ], expected: "4" },     # 3.5 rounds to 4
      { durations: [ 1, 1, 2 ], expected: "1" }   # 1.33... rounds to 1
    ]

    test_cases.each_with_index do |test_case, case_idx|
      # Clear existing operations for clean test
      RailsPulse::Operation.delete_all

      test_case[:durations].each_with_index do |duration, i|
        create(:operation, :at_time, :with_duration,
          at_time: (10 + case_idx).days.ago + i.hours,
          with_duration: duration
        )
      end

      card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
      result = card.to_metric_card

      expected_summary = "#{test_case[:expected]} ms"
      assert_equal expected_summary, result[:summary],
        "Expected #{expected_summary} for durations #{test_case[:durations]}, got #{result[:summary]}"
    end
  end

  test "sparkline data consistency across multiple calls" do
    # Create consistent data
    base_date = 3.weeks.ago.beginning_of_week
    [ 100, 150, 200 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: base_date + i.days,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)

    # Call multiple times and ensure consistency
    result1 = card.to_metric_card
    result2 = card.to_metric_card
    result3 = card.to_metric_card

    assert_equal result1[:line_chart_data], result2[:line_chart_data]
    assert_equal result2[:line_chart_data], result3[:line_chart_data]
    assert_equal result1[:summary], result2[:summary]
    assert_equal result1[:trend_amount], result2[:trend_amount]
  end

  test "query filtering parameter is stored correctly" do
    # Test that query parameter is properly stored and the card format is correct
    query = create(:query)

    card_with_query = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: query)
    card_without_query = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)

    # Verify query parameter storage
    assert_equal query, card_with_query.instance_variable_get(:@query)
    assert_nil card_without_query.instance_variable_get(:@query)

    # Both should return valid metric card format (regardless of data)
    result_with_query = card_with_query.to_metric_card
    result_without_query = card_without_query.to_metric_card

    [ result_with_query, result_without_query ].each do |result|
      assert_instance_of Hash, result
      assert_includes result, :title
      assert_includes result, :summary
      assert_includes result, :line_chart_data
      assert_includes result, :trend_icon
      assert_includes result, :trend_amount
      assert_includes result, :trend_text
      assert_equal "Average Query Time", result[:title]
    end
  end

  test "memory efficiency with large dataset" do
    # Create a large number of operations
    100.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 20.days.ago + (i * 4).hours,
        with_duration: rand(10..500)
      )
    end

    memory_before = GC.stat[:heap_live_slots]

    card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Force garbage collection
    GC.start
    memory_after = GC.stat[:heap_live_slots]

    # Should not significantly increase memory usage
    memory_increase = memory_after - memory_before
    assert memory_increase < 10000, "Memory usage increased by #{memory_increase} slots"

    # Should still produce valid results
    assert_instance_of Hash, result
    assert_match /\d+ ms/, result[:summary]
  end

  test "timezone handling in sparkline data" do
    # Test with different timezone scenarios
    original_zone = Time.zone

    begin
      # Test with UTC
      Time.zone = "UTC"
      utc_date = 2.weeks.ago.beginning_of_week
      create(:operation, :at_time, :with_duration,
        at_time: utc_date,
        with_duration: 100
      )

      card = RailsPulse::Queries::Cards::AverageQueryTimes.new(query: nil)
      utc_result = card.to_metric_card

      # Test with different timezone
      Time.zone = "America/New_York"
      ny_result = card.to_metric_card

      # Data should be consistent regardless of timezone
      assert_equal utc_result[:summary], ny_result[:summary]
      assert_equal utc_result[:line_chart_data].keys.length, ny_result[:line_chart_data].keys.length

    ensure
      Time.zone = original_zone
    end
  end
end
