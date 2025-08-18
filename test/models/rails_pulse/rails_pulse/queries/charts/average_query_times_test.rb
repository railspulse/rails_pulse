require "test_helper"

class RailsPulse::Queries::Charts::AverageQueryTimesTest < BaseChartTest
  def setup
    super
    @query = create(:query)
  end

  # Basic Functionality Tests

  test "initializes with required parameters" do
    ransack_query = RailsPulse::Request.ransack({})

    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      query: @query
    )

    assert_equal ransack_query, chart.instance_variable_get(:@ransack_query)
    assert_equal :group_by_day, chart.instance_variable_get(:@group_by)
    assert_equal @query, chart.instance_variable_get(:@query)
  end

  test "defaults to group_by_day when not specified" do
    ransack_query = RailsPulse::Request.ransack({})

    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query
    )

    assert_equal :group_by_day, chart.instance_variable_get(:@group_by)
  end

  # Request data path tests (when query is specified)

  test "processes request data when query is specified with daily grouping" do
    # Create requests with known durations
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date + 2.hours,
      with_duration: 100
    )
    create(:chart_request, :at_time, :with_duration,
      at_time: date + 4.hours,
      with_duration: 200
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      query: @query
    )

    result = chart.to_rails_chart

    assert_instance_of Hash, result

    # Should have data for the day we created requests
    expected_timestamp = date.beginning_of_day.to_i
    assert_includes result, expected_timestamp
    # Should calculate correct average: (100+200)/2 = 150.0
    assert_equal 150.0, result[expected_timestamp][:value]
  end

  # Operations data path tests (when query is nil)

  test "processes operations data when query is nil with daily grouping" do
    # Create operations with known durations
    date = 2.days.ago.beginning_of_day
    create(:operation, :at_time, :with_duration,
      at_time: date + 1.hour,
      with_duration: 50
    )
    create(:operation, :at_time, :with_duration,
      at_time: date + 3.hours,
      with_duration: 150
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      query: nil
    )

    result = chart.to_rails_chart

    assert_instance_of Hash, result

    # Should have data for the day we created operations
    expected_timestamp = date.beginning_of_day.to_i
    assert_includes result, expected_timestamp
    # Should calculate correct average: (50+150)/2 = 100.0
    assert_equal 100.0, result[expected_timestamp][:value]
  end

  # Time normalization tests

  test "normalizes timestamps correctly for daily grouping" do
    # Create request at specific time within day
    specific_time = 1.day.ago.beginning_of_day + 14.hours + 30.minutes
    create(:chart_request, :at_time, :with_duration,
      at_time: specific_time,
      with_duration: 125
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      query: @query
    )

    result = chart.to_rails_chart

    # Should normalize to beginning of day
    expected_timestamp = specific_time.beginning_of_day.to_i
    assert_includes result, expected_timestamp
    # Should return the duration value: 125.0
    assert_equal 125.0, result[expected_timestamp][:value]
  end

  # Data format tests

  test "returns data in correct rails chart format" do
    date = 3.days.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date,
      with_duration: 175
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: @query
    )

    result = chart.to_rails_chart

    assert_instance_of Hash, result

    timestamp = date.beginning_of_day.to_i
    assert_includes result, timestamp
    assert_instance_of Hash, result[timestamp]
    assert_includes result[timestamp], :value
    assert_instance_of Float, result[timestamp][:value]
    # Should return the duration value: 175.0
    assert_equal 175.0, result[timestamp][:value]
  end

  # Edge cases

  test "handles empty result set" do
    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: @query
    )

    result = chart.to_rails_chart

    assert_instance_of Hash, result
    # Should be empty when no data exists
    assert result.empty?, "Should be empty when no data exists"
  end

  test "handles nil average durations correctly" do
    # This would typically happen if there's no data for the period
    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: @query
    )

    result = chart.to_rails_chart

    assert_instance_of Hash, result
    # Should be empty when no data exists
    assert result.empty?, "Should be empty when no data exists"
  end

  # Multiple periods test

  test "handles multiple time periods correctly" do
    day1 = 3.days.ago.beginning_of_day
    day2 = 2.days.ago.beginning_of_day

    # Create requests for different days
    create(:chart_request, :at_time, :with_duration,
      at_time: day1,
      with_duration: 100
    )
    create(:chart_request, :at_time, :with_duration,
      at_time: day2,
      with_duration: 200
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: @query
    )

    result = chart.to_rails_chart

    # Should have data for both days
    assert result.any?, "Should have chart data"
    assert_equal 2, result.size, "Should have 2 data points for 2 different days"
    # Each day should have its respective value: 100.0 and 200.0
    assert result.values.any? { |v| v[:value] == 100.0 }, "Should include day1 value (100.0)"
    assert result.values.any? { |v| v[:value] == 200.0 }, "Should include day2 value (200.0)"
  end

  # Configuration tests

  test "works with different group_by options" do
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date,
      with_duration: 150
    )

    [ :group_by_hour, :group_by_day ].each do |group_by|
      ransack_query = RailsPulse::Request.ransack({})
      chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
        ransack_query: ransack_query,
        group_by: group_by,
        query: @query
      )

      result = chart.to_rails_chart

      assert_instance_of Hash, result

      # Should have some data
      assert result.keys.length > 0
      assert result.values.all? { |v| v.is_a?(Hash) && v.key?(:value) }
    end
  end

  # Query vs operations path differentiation

  test "uses request data path when query is present" do
    # Create both requests and operations
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date,
      with_duration: 100
    )
    create(:operation, :at_time, :with_duration,
      at_time: date,
      with_duration: 500
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: @query  # Query present - should use request data
    )

    result = chart.to_rails_chart

    # Should use request data (100), not operation data (500)
    assert result.any?, "Should have chart data"
    expected_timestamp = date.beginning_of_day.to_i
    assert_includes result, expected_timestamp
    assert_equal 100.0, result[expected_timestamp][:value]
  end

  test "uses operations data path when query is nil" do
    # Create both requests and operations
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date,
      with_duration: 100
    )
    create(:operation, :at_time, :with_duration,
      at_time: date,
      with_duration: 300
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: nil  # Query nil - should use operations data
    )

    result = chart.to_rails_chart

    expected_timestamp = date.beginning_of_day.to_i
    # Should use operation duration (300), not request duration (100)
    assert_includes result, expected_timestamp
    assert_equal 300.0, result[expected_timestamp][:value]
  end

  # Performance and edge case tests

  test "handles large datasets efficiently" do
    # Create many data points
    base_date = 7.days.ago.beginning_of_day
    100.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: base_date + (i * 2).hours,
        with_duration: rand(50..200)
      )
    end

    ransack_query = RailsPulse::Request.ransack({})

    start_time = Time.current
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: nil
    )
    result = chart.to_rails_chart
    execution_time = Time.current - start_time

    # Should complete efficiently
    assert execution_time < 2.0, "Chart generation took too long: #{execution_time}s"
    assert_instance_of Hash, result
    assert result.keys.length > 0
  end

  test "precision handling in average calculations" do
    date = 1.day.ago.beginning_of_day

    # Create operations with durations that result in fractional averages
    [ 33, 34, 35 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: date + i.hours,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: nil
    )

    result = chart.to_rails_chart

    expected_timestamp = date.beginning_of_day.to_i
    # Average of [33, 34, 35] = 34.0
    assert_includes result, expected_timestamp
    assert_equal 34.0, result[expected_timestamp][:value]
    assert_instance_of Float, result[expected_timestamp][:value]
  end

  test "handles operations with zero duration correctly" do
    date = 1.day.ago.beginning_of_day

    # Mix of zero and non-zero durations
    [ 0, 0, 100, 200 ].each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: date + i.hours,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: nil
    )

    result = chart.to_rails_chart

    expected_timestamp = date.beginning_of_day.to_i
    # Average of [0, 0, 100, 200] = 75.0
    assert_includes result, expected_timestamp
    assert_equal 75.0, result[expected_timestamp][:value]
  end

  test "consistency across multiple calls" do
    date = 2.days.ago.beginning_of_day
    create(:operation, :at_time, :with_duration,
      at_time: date,
      with_duration: 125
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: nil
    )

    # Multiple calls should return identical results
    result1 = chart.to_rails_chart
    result2 = chart.to_rails_chart
    result3 = chart.to_rails_chart

    assert_equal result1, result2
    assert_equal result2, result3
  end

  test "handles large duration values" do
    date = 1.day.ago.beginning_of_day

    # Test with large but database-compatible duration values
    large_durations = [ 500_000, 750_000, 999_999 ]
    large_durations.each_with_index do |duration, i|
      create(:operation, :at_time, :with_duration,
        at_time: date + i.hours,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Queries::Charts::AverageQueryTimes.new(
      ransack_query: ransack_query,
      query: nil
    )

    result = chart.to_rails_chart

    # Should have reasonable averages for large durations
    assert result.any?, "Should have chart data"
    expected_timestamp = date.beginning_of_day.to_i
    assert_includes result, expected_timestamp
    # Average of [500000, 750000, 999999] ≈ 749999.67
    assert_in_delta 749999.67, result[expected_timestamp][:value], 0.01
  end

  test "memory efficiency with concurrent access" do
    # Create baseline data
    date = 1.day.ago.beginning_of_day
    10.times do |i|
      create(:operation, :at_time, :with_duration,
        at_time: date + i.hours,
        with_duration: rand(50..150)
      )
    end

    ransack_query = RailsPulse::Request.ransack({})

    # Test multiple concurrent chart instances
    charts = Array.new(5) do
      RailsPulse::Queries::Charts::AverageQueryTimes.new(
        ransack_query: ransack_query,
        query: nil
      )
    end

    results = charts.map(&:to_rails_chart)

    # All results should be identical
    first_result = results.first
    results.each do |result|
      assert_equal first_result, result
    end
  end

  test "validates ransack_query parameter requirements" do
    # Should require ransack_query parameter
    assert_raises(ArgumentError) do
      RailsPulse::Queries::Charts::AverageQueryTimes.new
    end
  end
end
