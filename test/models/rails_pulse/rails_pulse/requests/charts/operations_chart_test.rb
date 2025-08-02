require "test_helper"

class RailsPulse::Requests::Charts::OperationsChartTest < BaseChartTest
  def setup
    super
  end

  # Basic Functionality Tests

  test "initializes with operations array" do
    operations = [
      create(:operation, start_time: 0, duration: 100),
      create(:operation, start_time: 50, duration: 150)
    ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    assert_equal operations, chart.instance_variable_get(:@operations)
    assert_not_nil chart.bars
    assert_not_nil chart.min_start
    assert_not_nil chart.max_end
    assert_not_nil chart.total_duration
  end

  test "handles empty operations array" do
    operations = []

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    assert_equal 0, chart.min_start
    assert_equal 1, chart.max_end  # Defaults to 1 to avoid division by zero
    assert_equal 1, chart.total_duration
    assert_empty chart.bars
  end

  # Bar calculation tests

  test "calculates bars correctly for single operation" do
    operation = create(:operation, start_time: 10, duration: 100)
    operations = [ operation ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    assert_equal 1, chart.bars.length

    bar = chart.bars.first
    assert_equal operation, bar.operation
    assert_equal 100, bar.duration  # Rounded to integer
    assert bar.left_pct.is_a?(Numeric)
    assert bar.width_pct.is_a?(Numeric)
  end

  test "calculates bars correctly for multiple operations" do
    operations = [
      create(:operation, start_time: 0, duration: 50),
      create(:operation, start_time: 25, duration: 75),
      create(:operation, start_time: 75, duration: 25)
    ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    assert_equal 3, chart.bars.length

    # Each bar should have required attributes
    chart.bars.each do |bar|
      assert_not_nil bar.operation
      assert_instance_of Integer, bar.duration
      assert bar.left_pct.is_a?(Numeric)
      assert bar.width_pct.is_a?(Numeric)
      assert bar.left_pct >= 0
      assert bar.left_pct <= 100
      assert bar.width_pct >= 0
      assert bar.width_pct <= 100
    end
  end

  # Duration calculation tests

  test "calculates min_start correctly" do
    operations = [
      create(:operation, start_time: 10, duration: 50),
      create(:operation, start_time: 5, duration: 25),
      create(:operation, start_time: 15, duration: 75)
    ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    assert_equal 5, chart.min_start  # Minimum start time
  end

  test "calculates max_end correctly" do
    operations = [
      create(:operation, start_time: 10, duration: 50),  # Ends at 60
      create(:operation, start_time: 5, duration: 25),   # Ends at 30
      create(:operation, start_time: 15, duration: 75)   # Ends at 90
    ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    assert_equal 90, chart.max_end  # Maximum end time (15 + 75)
  end

  test "calculates total_duration correctly" do
    operations = [
      create(:operation, start_time: 10, duration: 50),  # Ends at 60
      create(:operation, start_time: 5, duration: 25),   # Ends at 30
      create(:operation, start_time: 15, duration: 75)   # Ends at 90
    ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    # Total duration should be max_end - min_start = 90 - 5 = 85
    assert_equal 85, chart.total_duration
  end

  # Percentage calculation tests

  test "calculates percentage positions correctly for simple case" do
    operations = [
      create(:operation, start_time: 0, duration: 50),   # From 0 to 50
      create(:operation, start_time: 25, duration: 25)   # From 25 to 50
    ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    # Total duration is 50 (0 to 50)
    # First operation: starts at 0%, width 100%
    # Second operation: starts at 50%, width 50%

    first_bar = chart.bars[0]
    second_bar = chart.bars[1]

    # Verify positions are reasonable (exact values depend on px_to_pct calculation)
    assert first_bar.left_pct >= 0
    assert first_bar.left_pct < second_bar.left_pct
    assert first_bar.width_pct > second_bar.width_pct
  end

  # Edge cases

  test "handles operations with zero duration" do
    operation = create(:operation, start_time: 10, duration: 0)
    operations = [ operation ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    bar = chart.bars.first
    assert_equal 0, bar.duration
    assert bar.left_pct.is_a?(Numeric)
    assert bar.width_pct.is_a?(Numeric)
  end

  test "handles operations with same start time" do
    operations = [
      create(:operation, start_time: 10, duration: 50),
      create(:operation, start_time: 10, duration: 75)
    ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    # Both should have same left percentage
    first_bar = chart.bars[0]
    second_bar = chart.bars[1]

    assert_equal first_bar.left_pct, second_bar.left_pct
    assert_not_equal first_bar.width_pct, second_bar.width_pct
  end

  test "handles fractional durations with rounding" do
    operation = create(:operation, start_time: 0, duration: 123.7)
    operations = [ operation ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    bar = chart.bars.first
    assert_equal 124, bar.duration  # Should be rounded to nearest integer
  end

  # OperationBar struct tests

  test "OperationBar struct has correct attributes" do
    operation = create(:operation, start_time: 5, duration: 100)

    bar = RailsPulse::Requests::Charts::OperationsChart::OperationBar.new(
      operation,
      100,
      25.5,
      50.0
    )

    assert_equal operation, bar.operation
    assert_equal 100, bar.duration
    assert_equal 25.5, bar.left_pct
    assert_equal 50.0, bar.width_pct
  end

  # Pixel offset tests

  test "pixel offset calculation is consistent" do
    operations = [ create(:operation, start_time: 0, duration: 100) ]
    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    # px_to_pct should be consistent
    px_to_pct = chart.send(:px_to_pct)
    assert px_to_pct.is_a?(Numeric)
    assert px_to_pct > 0
    assert px_to_pct < 100
  end

  # Complex scenario tests

  test "handles complex overlapping operations" do
    operations = [
      create(:operation, start_time: 0, duration: 100),   # 0-100
      create(:operation, start_time: 25, duration: 50),   # 25-75
      create(:operation, start_time: 50, duration: 75),   # 50-125
      create(:operation, start_time: 100, duration: 25)   # 100-125
    ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    assert_equal 4, chart.bars.length
    assert_equal 0, chart.min_start
    assert_equal 125, chart.max_end
    assert_equal 125, chart.total_duration

    # Verify all bars have valid percentages
    chart.bars.each do |bar|
      assert bar.left_pct >= 0
      assert bar.left_pct <= 100
      assert bar.width_pct >= 0
      assert bar.width_pct <= 100
    end
  end

  test "maintains operation order in bars" do
    operations = [
      create(:operation, :sql, start_time: 10, duration: 50),
      create(:operation, :controller, start_time: 5, duration: 25),
      create(:operation, :template, start_time: 15, duration: 75)
    ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    # Bars should maintain same order as input operations
    assert_equal operations[0], chart.bars[0].operation
    assert_equal operations[1], chart.bars[1].operation
    assert_equal operations[2], chart.bars[2].operation
  end

  # Performance tests

  test "handles large number of operations efficiently" do
    operations = 100.times.map do |i|
      create(:operation, start_time: i * 10, duration: rand(50..150))
    end

    start_time = Time.current
    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)
    end_time = Time.current

    # Should complete quickly
    assert (end_time - start_time) < 1.0  # Less than 1 second

    assert_equal 100, chart.bars.length
    assert chart.min_start >= 0
    assert chart.max_end > chart.min_start
    assert chart.total_duration > 0
  end

  # Integration with actual operation types

  test "works with different operation types" do
    operations = [
      create(:operation, :sql, start_time: 0, duration: 100),
      create(:operation, :controller, start_time: 50, duration: 75),
      create(:operation, :template, start_time: 100, duration: 50)
    ]

    chart = RailsPulse::Requests::Charts::OperationsChart.new(operations)

    assert_equal 3, chart.bars.length

    # Each bar should reference the correct operation type
    assert_equal "sql", chart.bars[0].operation.operation_type
    assert_equal "controller", chart.bars[1].operation.operation_type
    assert_equal "template", chart.bars[2].operation.operation_type
  end
end
