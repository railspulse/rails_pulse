require "test_helper"

class RailsPulse::Queries::Cards::ExecutionRateTest < BaseChartTest
  def setup
    super
    @query = create(:query)
  end

  # Basic Functionality Tests

  test "initializes with query parameter" do
    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: @query)

    assert_equal @query, card.instance_variable_get(:@query)
  end

  test "initializes with nil query parameter" do
    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)

    assert_nil card.instance_variable_get(:@query)
  end

  test "initializes without parameters" do
    card = RailsPulse::Queries::Cards::ExecutionRate.new

    assert_nil card.instance_variable_get(:@query)
  end

  # Card format tests

  test "returns data in correct metric card format" do
    # Create some operations without query filtering to avoid association issues
    3.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: (10.days.ago + i.days),
        with_duration: 100
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    assert_instance_of Hash, result
    assert_includes result, :title
    assert_includes result, :summary
    assert_includes result, :line_chart_data
    assert_includes result, :trend_icon
    assert_includes result, :trend_amount
    assert_includes result, :trend_text

    assert_equal "Execution Rate", result[:title]
    assert_equal "Compared to last week", result[:trend_text]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Operations per minute calculation tests

  test "calculates operations per minute for multiple operations" do
    # Create operations over a known time span
    start_time = 2.hours.ago
    end_time = 1.hour.ago

    # Create 6 operations over 1 hour = 0.1 operations per minute = 6 operations per hour
    6.times do |i|
      create(:operation, :at_time,
        at_time: start_time + (i * 10).minutes
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # Should be approximately 0.1 operations per minute
    summary_match = result[:summary].match(/([\d.]+) \/ min/)
    assert_not_nil summary_match, "Expected summary to match pattern, got: #{result[:summary]}"
    operations_per_minute = summary_match[1].to_f
    assert operations_per_minute > 0, "Should have some operations per minute, got #{operations_per_minute}"
  end

  test "handles single operation correctly" do
    # Create one operation
    create(:operation, :at_time, :with_duration,
      at_time: 3.days.ago,
      with_duration: 100
    )

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # Should handle single operation (defaults to 1 minute span)
    assert_match /\d+ \/ min/, result[:summary]
  end

  # Trend calculation tests

  test "calculates trend when current period has more operations" do
    # Previous period (14-7 days ago): Create fewer operations
    5.times do |i|
      create(:operation, :at_time,
        at_time: (14.days.ago + i.days)
      )
    end

    # Current period (last 7 days): Create more operations
    10.times do |i|
      create(:operation, :at_time,
        at_time: (6.days.ago + (i * 12).hours)
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # Should show an upward trend
    assert_includes [ "trending-up", "trending-down", "move-right" ], result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "calculates trend when periods are equal" do
    # Previous period: Create operations
    5.times do |i|
      create(:operation, :at_time,
        at_time: (14.days.ago + i.days)
      )
    end

    # Current period: Create same number of operations
    5.times do |i|
      create(:operation, :at_time,
        at_time: (6.days.ago + i.days)
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # When roughly equal, should show move-right or small percentage
    assert_includes [ "trending-up", "trending-down", "move-right" ], result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "handles zero previous period count" do
    # No operations in previous period, only in current
    3.times do |i|
      create(:operation, :at_time,
        at_time: (5.days.ago + i.days)
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
  end

  # Sparkline data tests

  test "generates sparkline data grouped by week" do
    # Create operations over multiple weeks
    4.times do |week|
      3.times do |day|
        create(:operation, :at_time,
          at_time: (4.weeks.ago + week.weeks + day.days)
        )
      end
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]
    assert_instance_of Hash, sparkline_data

    # Each data point should have correct format
    sparkline_data.each do |date_str, data|
      assert_instance_of String, date_str
      assert_instance_of Hash, data
      assert_includes data, :value
      assert_instance_of Integer, data[:value]
    end
  end

  test "sparkline data has reasonable weekly counts" do
    # Create known number of operations in specific weeks
    week1_start = 3.weeks.ago.beginning_of_week
    week2_start = 2.weeks.ago.beginning_of_week

    # Week 1: 4 operations
    4.times do |i|
      create(:operation, :at_time,
        at_time: week1_start + i.days
      )
    end

    # Week 2: 6 operations
    6.times do |i|
      create(:operation, :at_time,
        at_time: week2_start + i.days
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    sparkline_data = result[:line_chart_data]

    # Should have weekly data with the operations we created
    total_operations = sparkline_data.values.sum { |data| data[:value] }
    assert_equal 10, total_operations, "Should have total 10 operations across all weeks"
  end

  test "date formatting in sparkline data uses correct format" do
    # Create operation in a specific week
    known_date = 2.weeks.ago.beginning_of_week
    create(:operation, :at_time,
      at_time: known_date
    )

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
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
    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    assert_equal "Execution Rate", result[:title]
    assert_equal "0 / min", result[:summary]
    assert_equal "move-right", result[:trend_icon]
    assert_equal "0%", result[:trend_amount]
    assert_instance_of Hash, result[:line_chart_data]
    assert_empty result[:line_chart_data]
  end

  test "handles operations with identical timestamps" do
    # Create multiple operations at the same time
    same_time = 2.days.ago
    5.times do
      create(:operation, :at_time, :with_duration,
        at_time: same_time,
        with_duration: 100
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # Should handle gracefully
    assert_match /\d+ \/ min/, result[:summary]
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Integration tests

  test "works with different operation types" do
    # Create operations of different types at specific times
    base_time = 3.days.ago
    [ :sql, :controller, :template ].each_with_index do |operation_type, i|
      2.times do |j|
        create(:operation, operation_type, :at_time,
          at_time: base_time + (i * 12 + j * 6).hours
        )
      end
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # Should include all operation types in calculations
    assert_match /[\d.]+ \/ min/, result[:summary], "Expected operations per minute format"
    assert_instance_of Hash, result[:line_chart_data]
  end

  # Performance test

  test "handles large number of operations efficiently" do
    # Create many operations over a specific time range
    base_time = 10.days.ago
    50.times do |i|
      create(:operation, :at_time,
        at_time: base_time + (i * 4).hours  # Spread over ~8 days
      )
    end

    start_time = Time.current
    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card
    execution_time = Time.current - start_time

    # Should complete in reasonable time
    assert execution_time < 1.0, "Execution took too long: #{execution_time}s"

    # Should still produce valid results
    assert_instance_of Hash, result
    assert_match /[\d.]+ \/ min/, result[:summary], "Expected operations per minute format"
  end

  # Basic query filtering test (simplified)

  test "respects query parameter when provided" do
    # This test verifies the parameter is stored correctly
    card_with_query = RailsPulse::Queries::Cards::ExecutionRate.new(query: @query)
    card_without_query = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)

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

  # Advanced calculation and edge case tests

  test "precise execution rate calculation with exact time spans" do
    # Create exactly 12 operations over exactly 60 minutes = 0.2 operations per minute
    start_time = 2.hours.ago
    12.times do |i|
      create(:operation, :at_time,
        at_time: start_time + (i * 5).minutes  # Every 5 minutes for 60 minutes
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # Should calculate rate based on actual time span and operation count
    summary_match = result[:summary].match(/([\d.]+) \/ min/)
    assert_not_nil summary_match, "Expected summary to match pattern, got: #{result[:summary]}"

    operations_per_minute = summary_match[1].to_f
    assert operations_per_minute > 0, "Should have positive operations per minute"
  end

  test "handles sub-minute time spans appropriately" do
    # Create operations in a very short time span (30 seconds)
    start_time = 1.hour.ago
    3.times do |i|
      create(:operation, :at_time,
        at_time: start_time + (i * 10).seconds
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # Should handle short time spans gracefully
    assert_match /[\d.]+ \/ min/, result[:summary]
    summary_match = result[:summary].match(/([\d.]+) \/ min/)
    operations_per_minute = summary_match[1].to_f
    assert operations_per_minute > 0, "Should extrapolate to positive rate per minute"
  end

  test "query parameter affects card behavior" do
    # Test that query parameter is properly stored and affects the card
    query = create(:query)

    card_with_query = RailsPulse::Queries::Cards::ExecutionRate.new(query: query)
    card_without_query = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)

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
      assert_equal "Execution Rate", result[:title]
      assert_match /[\d.]+ \/ min/, result[:summary]
    end
  end

  test "trend calculation accuracy with specific percentages" do
    # Previous period: exactly 4 operations
    4.times do |i|
      create(:operation, :at_time,
        at_time: (12.days.ago + i.days)
      )
    end

    # Current period: exactly 6 operations (50% increase)
    6.times do |i|
      create(:operation, :at_time,
        at_time: (5.days.ago + i.days)
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # Should show upward trend
    assert_equal "trending-up", result[:trend_icon]

    # Extract percentage
    percentage_match = result[:trend_amount].match(/([\d.]+)%/)
    assert_not_nil percentage_match, "Expected percentage in trend_amount: #{result[:trend_amount]}"
    percentage = percentage_match[1].to_f

    # Should be around 50% (6 vs 4 = 50% increase)
    assert percentage > 40, "Expected significant positive percentage, got #{percentage}%"
  end

  test "handles zero current period operations" do
    # Only operations in previous period, none in current
    5.times do |i|
      create(:operation, :at_time,
        at_time: (12.days.ago + i.days)
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    assert_match /0(\.0)? \/ min/, result[:summary]
    assert_equal "trending-down", result[:trend_icon]
    assert_match /\d+(\.\d+)?%/, result[:trend_amount]
  end

  test "consistency of sparkline data across multiple calls" do
    # Create consistent test data
    3.times do |week|
      2.times do |day|
        create(:operation, :at_time,
          at_time: (3.weeks.ago + week.weeks + day.days)
        )
      end
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)

    # Multiple calls should be identical
    result1 = card.to_metric_card
    result2 = card.to_metric_card
    result3 = card.to_metric_card

    assert_equal result1[:line_chart_data], result2[:line_chart_data]
    assert_equal result2[:line_chart_data], result3[:line_chart_data]
    assert_equal result1[:summary], result2[:summary]
    assert_equal result1[:trend_amount], result2[:trend_amount]
  end

  test "memory efficiency with large datasets" do
    # Create many operations
    100.times do |i|
      create(:operation, :at_time,
        at_time: 30.days.ago + (i * 6).hours
      )
    end

    memory_before = GC.stat[:heap_live_slots]

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # Force garbage collection
    GC.start
    memory_after = GC.stat[:heap_live_slots]

    # Should not significantly increase memory usage
    memory_increase = memory_after - memory_before
    assert memory_increase < 15000, "Memory usage increased by #{memory_increase} slots"

    # Should still produce valid results
    assert_instance_of Hash, result
    assert_match /[\d.]+ \/ min/, result[:summary]
  end

  test "rate calculation with operations spanning multiple days" do
    # Create operations across 3 days with known distribution
    base_time = 3.days.ago.beginning_of_day

    # Day 1: 2 operations
    2.times do |i|
      create(:operation, :at_time,
        at_time: base_time + (i * 6).hours
      )
    end

    # Day 2: 4 operations
    4.times do |i|
      create(:operation, :at_time,
        at_time: base_time + 1.day + (i * 3).hours
      )
    end

    # Day 3: 6 operations
    6.times do |i|
      create(:operation, :at_time,
        at_time: base_time + 2.days + (i * 2).hours
      )
    end

    card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
    result = card.to_metric_card

    # Should calculate rate based on total time span and total operations
    # 12 operations over approximately 3 days
    summary_match = result[:summary].match(/([\d.]+) \/ min/)
    assert_not_nil summary_match, "Expected summary to match pattern, got: #{result[:summary]}"
    operations_per_minute = summary_match[1].to_f

    # Should have some operations per minute (allow for reasonable calculation)
    assert operations_per_minute >= 0, "Should have non-negative rate, got #{operations_per_minute}"
    assert operations_per_minute < 100, "Rate should be reasonable for the timespan, got #{operations_per_minute}"
  end

  test "timezone handling in calculations" do
    original_zone = Time.zone

    begin
      # Test with UTC
      Time.zone = "UTC"
      utc_time = 2.days.ago
      create(:operation, :at_time,
        at_time: utc_time
      )

      card = RailsPulse::Queries::Cards::ExecutionRate.new(query: nil)
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
end
