require "test_helper"

module RailsPulse
  class StatisticsTest < ActiveSupport::TestCase
    # Percentile Calculation Tests

    test "calculate_percentile returns nil for empty array" do
      result = Statistics.calculate_percentile([], 0.95)

      assert_nil result
    end

    test "calculate_percentile returns single value for single-element array" do
      result = Statistics.calculate_percentile([ 500.0 ], 0.95)

      assert_in_delta 500.0, result, 0.01
    end

    test "calculate_percentile handles identical values" do
      values = [ 300.0 ] * 5

      result = Statistics.calculate_percentile(values, 0.95)

      assert_in_delta 300.0, result, 0.01
    end

    test "calculate_percentile calculates p95 with linear interpolation" do
      # Sorted: [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
      # n=10, rank = 0.95*9 = 8.55
      # lerp(900, 1000, 0.55) = 955
      values = (1..10).map { |i| i * 100.0 }

      result = Statistics.calculate_percentile(values, 0.95)

      assert_in_delta 955.0, result, 1.0
    end

    test "calculate_percentile calculates p99 with linear interpolation" do
      # n=10, rank = 0.99*9 = 8.91
      # lerp(900, 1000, 0.91) = 991
      values = (1..10).map { |i| i * 100.0 }

      result = Statistics.calculate_percentile(values, 0.99)

      assert_in_delta 991.0, result, 1.0
    end

    test "calculate_percentile handles median (p50)" do
      values = [ 100, 200, 300, 400, 500 ]

      result = Statistics.calculate_percentile(values, 0.50)

      assert_in_delta 300.0, result, 0.01
    end

    test "calculate_percentile handles boundary at 0th percentile" do
      values = [ 100, 200, 300, 400, 500 ]

      result = Statistics.calculate_percentile(values, 0.0)

      assert_in_delta 100.0, result, 0.01
    end

    test "calculate_percentile handles boundary at 100th percentile" do
      values = [ 100, 200, 300, 400, 500 ]

      result = Statistics.calculate_percentile(values, 1.0)

      assert_in_delta 500.0, result, 0.01
    end

    test "calculate_percentile works with two values" do
      values = [ 100, 200 ]

      result = Statistics.calculate_percentile(values, 0.50)

      assert_in_delta 150.0, result, 0.01
    end

    test "calculate_percentile handles large datasets" do
      values = (1..100).map { |i| i * 10.0 }

      result = Statistics.calculate_percentile(values, 0.95)

      # p95 of 1-100 scaled by 10 should be around 950
      assert_in_delta 955.0, result, 5.0
    end

    # Standard Deviation Tests

    test "calculate_stddev returns nil for empty array" do
      result = Statistics.calculate_stddev([], 100)

      assert_nil result
    end

    test "calculate_stddev returns nil for single-element array" do
      result = Statistics.calculate_stddev([ 100 ], 100)

      assert_nil result
    end

    test "calculate_stddev calculates standard deviation correctly" do
      values = [ 100, 200, 300, 400, 500 ]
      mean = 300.0
      # Expected stddev ≈ 158.11

      result = Statistics.calculate_stddev(values, mean)

      assert_in_delta 158.11, result, 1.0
    end

    test "calculate_stddev handles zero variance" do
      values = [ 100, 100, 100, 100 ]
      mean = 100.0

      result = Statistics.calculate_stddev(values, mean)

      assert_in_delta 0.0, result, 0.01
    end

    test "calculate_stddev works with two values" do
      values = [ 100, 200 ]
      mean = 150.0

      result = Statistics.calculate_stddev(values, mean)

      # Stddev of [100, 200] with mean 150 = sqrt(5000) ≈ 70.71
      assert_in_delta 70.71, result, 1.0
    end

    test "calculate_stddev handles negative values" do
      values = [ -100, -50, 0, 50, 100 ]
      mean = 0.0

      result = Statistics.calculate_stddev(values, mean)

      assert_in_delta 79.06, result, 1.0
    end
  end
end
