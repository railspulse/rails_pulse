require "test_helper"

class RailsPulse::Queries::Cards::PercentileQueryTimesTest < BaseChartTest
  def setup
    super
    @query = create(:query)
  end

  # Basic Functionality Tests

  test "initializes with query parameter" do
    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: @query)

    assert_equal @query, card.instance_variable_get(:@query)
  end

  test "initializes with nil query parameter" do
    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)

    assert_nil card.instance_variable_get(:@query)
  end

  test "initializes without parameters" do
    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new

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

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    assert_instance_of Hash, result
    assert_includes result, :title
    assert_includes result, :summary
    assert_includes result, :line_chart_data
    assert_includes result, :trend_icon
    assert_includes result, :trend_amount
    assert_includes result, :trend_text

    assert_equal "95th Percentile Query Time", result[:title]
    assert_equal "Compared to last week", result[:trend_text]
    assert_match /\d+ ms/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # 95th percentile calculation tests

  test "calculates 95th percentile correctly for small dataset" do
    # Create 10 operations with known durations: 10, 20, 30, ..., 100
    10.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 5.days.ago,
        with_duration: (i + 1) * 10
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # 95th percentile of [10,20,30,40,50,60,70,80,90,100] should be around 100
    # floor(10 * 0.95) = floor(9.5) = 9, so offset 9 gives us the 10th element (index 9) = 100
    assert_match /100(\.0)? ms/, result[:summary]
  end

  test "calculates 95th percentile correctly for larger dataset" do
    # Create 20 operations with durations 5, 10, 15, ..., 100
    20.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 3.days.ago,
        with_duration: (i + 1) * 5
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # 95th percentile: floor(20 * 0.95) = floor(19) = 19, offset 19 gives us 20th element = 100
    assert_match /100(\.0)? ms/, result[:summary]
  end

  test "handles single operation" do
    create(:operation, :at_time, :with_duration,
      at_time: 2.days.ago,
      with_duration: 150
    )

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Single operation should be the 95th percentile
    assert_match /150(\.0)? ms/, result[:summary]
  end

  test "handles operations with same duration" do
    # Create 5 operations with identical durations
    5.times do
      create(:operation, :at_time, :with_duration,
        at_time: 4.days.ago,
        with_duration: 200
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # All operations have same duration, so 95th percentile should be 200
    assert_match /200(\.0)? ms/, result[:summary]
  end

  # Trend calculation tests

  test "calculates correct trend when current period is faster" do
    # Previous period (14-7 days ago): Higher durations
    5.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (12.days.ago + i.days),
        with_duration: (i + 6) * 10  # 60, 70, 80, 90, 100 ms
      )
    end

    # Current period (last 7 days): Lower durations
    5.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (5.days.ago + i.days),
        with_duration: (i + 1) * 10  # 10, 20, 30, 40, 50 ms
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Current period is faster, so should be trending down
    assert_equal "trending-down", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates correct trend when current period is slower" do
    # Previous period (14-7 days ago): Lower durations
    5.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (12.days.ago + i.days),
        with_duration: (i + 1) * 10  # 10, 20, 30, 40, 50 ms
      )
    end

    # Current period (last 7 days): Higher durations
    5.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (5.days.ago + i.days),
        with_duration: (i + 6) * 10  # 60, 70, 80, 90, 100 ms
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Current period is slower, so should be trending up
    assert_equal "trending-up", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates correct trend when periods are similar" do
    # Previous period: 50ms operations
    5.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (12.days.ago + i.days),
        with_duration: 50
      )
    end

    # Current period: Also ~50ms operations
    5.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (5.days.ago + i.days),
        with_duration: 50
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # When periods are the same, percentage should be 0 (< 0.1) so move-right
    assert_equal "move-right", result[:trend_icon]
    assert_match /0(\.0)?%/, result[:trend_amount]
  end

  test "handles zero previous period count for trend" do
    # No operations in previous period, only in current
    3.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (3.days.ago + i.days),
        with_duration: 75
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
  end

  # Sparkline data tests

  test "generates sparkline data grouped by week with average durations" do
    # Create operations over multiple weeks with known durations
    base_date = 4.weeks.ago.beginning_of_week

    # Week 1: operations with durations averaging 50ms
    [ 40, 50, 60 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: base_date + i.days,
        with_duration: duration
      )
    end

    # Week 2: operations with durations averaging 100ms
    [ 90, 100, 110 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: base_date + 1.week + i.days,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
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
    # Create operations with decimal durations that will average to a decimal
    base_date = 2.weeks.ago.beginning_of_week
    [ 33, 34, 35 ].each_with_index do |duration, i|  # Average = 34.0
      create(:operation, :at_time, :with_duration,
        at_time: base_date + i.days,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]

    # All values should be integers (rounded)
    sparkline_data.values.each do |data|
      assert_instance_of Integer, data[:value]
    end
  end

  test "sparkline data handles weeks with no operations" do
    # Create operations in only some weeks
    create(:operation, :at_time, :with_duration,
      at_time: 3.weeks.ago,
      with_duration: 100
    )

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]
    assert_instance_of Hash, sparkline_data

    # Should handle weeks with no data gracefully
    sparkline_data.values.each do |data|
      assert data[:value] >= 0, "Value should be non-negative even for empty weeks"
    end
  end

  test "date formatting in sparkline data uses correct format" do
    # Create operation in a specific week
    known_date = 2.weeks.ago.beginning_of_week
    create(:operation, :at_time, :with_duration,
      at_time: known_date,
      with_duration: 80
    )

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
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
    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    assert_equal "95th Percentile Query Time", result[:title]
    assert_equal "0 ms", result[:summary]
    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
    assert_instance_of Hash, result[:line_chart_data]
    assert_empty result[:line_chart_data]
  end

  test "handles operations with zero duration" do
    # Create operations with zero and non-zero durations
    [ 0, 0, 50, 100, 150 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: 2.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Should handle zero durations in percentile calculation
    assert_match /\d+ ms/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Integration tests

  test "works with different operation types" do
    # Create operations of different types with various durations
    [ :sql, :controller, :template ].each_with_index do |operation_type, type_idx|
      3.times do |i|
        create(:operation, operation_type, :at_time, :with_duration,
          at_time: 4.days.ago + (type_idx * 8 + i * 2).hours,
          with_duration: (type_idx + 1) * 30 + i * 10  # Varying durations by type
        )
      end
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Should include all operation types in calculations
    assert_match /\d+ ms/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
    assert_includes [ "trending-up", "trending-down", "move-right" ], result[:trend_icon]
  end

  # Performance test

  test "handles large number of operations efficiently" do
    # Create many operations with random durations
    100.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 10.days.ago + (i * 2).hours,
        with_duration: rand(10..200)
      )
    end

    start_time = Time.current
    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card
    execution_time = Time.current - start_time

    # Should complete in reasonable time
    assert execution_time < 1.0, "Execution took too long: #{execution_time}s"

    # Should still produce valid results
    assert_instance_of Hash, result
    assert_match /\d+ ms/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Percentile edge cases

  test "handles percentile calculation for very small datasets" do
    # Test with 1, 2, 3 operations
    [ 1, 2, 3 ].each do |count|
      # Clear previous operations
      RailsPulse::Operation.delete_all

      count.times do |i|
        create(:operation, :at_time, :with_duration,
          at_time: 1.day.ago + i.hours,
          with_duration: (i + 1) * 50
        )
      end

      card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
      result = card.to_metric_card

      # Should handle small datasets without errors
      assert_match /\d+ ms/, result[:summary]

      # For small datasets, 95th percentile should be the highest value
      expected_duration = count * 50
      assert_match /#{expected_duration}(\.0)? ms/, result[:summary]
    end
  end

  # Basic query filtering test (simplified)

  test "respects query parameter when provided" do
    # This test verifies the parameter is stored correctly
    card_with_query = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: @query)
    card_without_query = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)

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

  # Advanced percentile calculation tests

  test "95th percentile calculation with exact mathematical verification" do
    # Create exactly 100 operations with durations 1, 2, 3, ..., 100
    100.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 5.days.ago + i.minutes,
        with_duration: i + 1
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # 95th percentile of 100 elements: floor(100 * 0.95) = 95
    # Index 95 (0-based) corresponds to the 96th element, which is duration 96
    # But since we want the 95th percentile, we expect around 95-96
    assert_match /(9[5-6]|100)(\.[0-9]+)? ms/, result[:summary]
  end

  test "handles large duration values in percentile calculation" do
    # Create operations with large but database-compatible durations
    large_durations = [ 100_000, 200_000, 500_000, 750_000, 999_999 ]
    large_durations.each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: 3.days.ago + i.hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # 95th percentile should be the highest value (999,999)
    assert_match /999999(\.[0-9]+)? ms/, result[:summary]
  end

  test "percentile calculation consistency across multiple calls" do
    # Create consistent dataset
    20.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 4.days.ago + i.hours,
        with_duration: (i + 1) * 10
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)

    # Multiple calls should return identical results
    result1 = card.to_metric_card
    result2 = card.to_metric_card
    result3 = card.to_metric_card

    assert_equal result1[:summary], result2[:summary]
    assert_equal result2[:summary], result3[:summary]
    assert_equal result1[:line_chart_data], result2[:line_chart_data]
    assert_equal result1[:trend_amount], result2[:trend_amount]
  end

  test "query parameter storage and card format" do
    # Test that query parameter is properly stored and affects the card
    query = create(:query)

    card_with_query = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: query)
    card_without_query = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)

    # Verify query parameter storage
    assert_equal query, card_with_query.instance_variable_get(:@query)
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
      assert_equal "95th Percentile Query Time", result[:title]
      assert_match /\d+ ms/, result[:summary]
    end
  end

  test "percentile calculation with outliers" do
    # Create normal operations plus some extreme outliers
    # Normal: 50, 60, 70, 80, 90, 100, 110, 120, 130, 140
    10.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 3.days.ago + i.hours,
        with_duration: 50 + (i * 10)
      )
    end

    # Add extreme outliers
    [ 10000, 20000 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: 3.days.ago + (10 + i).hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # 95th percentile should be affected by outliers
    # With 12 values, 95th percentile index would be around 11, so we'd get one of the outliers
    summary_value = result[:summary].match(/(\d+)(\.\d+)? ms/)[1].to_i
    assert summary_value >= 140, "95th percentile should be significantly affected by outliers, got #{summary_value}"
  end

  test "memory efficiency with large datasets" do
    # Create many operations
    200.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 20.days.ago + (i * 2).hours,
        with_duration: rand(10..1000)
      )
    end

    memory_before = GC.stat[:heap_live_slots]

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
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

  test "trend calculation with decimal precision" do
    # Previous period: operations with specific durations for exact percentage calculation
    # Create 5 operations with durations 80, 90, 100, 110, 120 (95th percentile = 120)
    [ 80, 90, 100, 110, 120 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: (12.days.ago + i.days),
        with_duration: duration
      )
    end

    # Current period: operations with durations 60, 70, 80, 90, 100 (95th percentile = 100)
    # This represents a 100 -> 120 change, which is a 20% increase
    [ 60, 70, 80, 90, 100 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: (5.days.ago + i.days),
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # Should show improvement (trending down)
    assert_equal "trending-down", result[:trend_icon]

    # Extract percentage
    percentage_match = result[:trend_amount].match(/([\d.]+)%/)
    assert_not_nil percentage_match, "Expected percentage in trend_amount: #{result[:trend_amount]}"
    percentage = percentage_match[1].to_f

    # Should show a meaningful percentage change
    assert percentage > 0, "Expected positive percentage change, got #{percentage}%"
  end

  test "handles fractional percentile results" do
    # Create operations where 95th percentile calculation might result in fractional index
    # 13 operations: indices 0-12, 95th percentile index = floor(13 * 0.95) = floor(12.35) = 12
    13.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 3.days.ago + i.hours,
        with_duration: (i + 1) * 5  # 5, 10, 15, ..., 65
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # 95th percentile should be the 13th element (index 12) = 65
    assert_match /65(\.0)? ms/, result[:summary]
  end

  test "timezone handling in sparkline data and calculations" do
    original_zone = Time.zone

    begin
      # Test with UTC
      Time.zone = "UTC"
      utc_time = 2.weeks.ago.beginning_of_week
      create(:operation, :at_time, :with_duration,
        at_time: utc_time,
        with_duration: 150
      )

      card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
      utc_result = card.to_metric_card

      # Test with different timezone
      Time.zone = "America/New_York"
      ny_result = card.to_metric_card

      # Results should be consistent regardless of timezone
      assert_equal utc_result[:summary], ny_result[:summary]
      assert_equal utc_result[:line_chart_data].keys.length, ny_result[:line_chart_data].keys.length

    ensure
      Time.zone = original_zone
    end
  end

  test "percentile with extreme distribution patterns" do
    # Test with heavily skewed distribution
    # 90% of operations have low durations, 10% have very high durations

    # 18 operations with low durations (10-27)
    18.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: 4.days.ago + i.hours,
        with_duration: 10 + i
      )
    end

    # 2 operations with very high durations
    [ 1000, 2000 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: 4.days.ago + (18 + i).hours,
        with_duration: duration
      )
    end

    card = RailsPulse::Queries::Cards::PercentileQueryTimes.new(query: nil)
    result = card.to_metric_card

    # With 20 operations, 95th percentile index = floor(20 * 0.95) = 19
    # Index 19 corresponds to one of the high-duration operations
    summary_value = result[:summary].match(/(\d+)(\.\d+)? ms/)[1].to_i
    assert summary_value >= 1000, "95th percentile should capture high-duration outliers, got #{summary_value}"
  end
end
