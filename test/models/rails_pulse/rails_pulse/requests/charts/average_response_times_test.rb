require "test_helper"

class RailsPulse::Requests::Charts::AverageResponseTimesTest < BaseChartTest
  def setup
    super
    @route = create(:route)
  end

  # Basic Functionality Tests

  test "initializes with required parameters" do
    ransack_query = RailsPulse::Request.ransack({})

    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      group_by: :group_by_day,
      route: @route
    )

    assert_equal ransack_query, chart.instance_variable_get(:@ransack_query)
    assert_equal :group_by_day, chart.instance_variable_get(:@group_by)
    assert_equal @route, chart.instance_variable_get(:@route)
  end

  test "defaults to group_by_day when not specified" do
    ransack_query = RailsPulse::Request.ransack({})

    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query
    )

    assert_equal :group_by_day, chart.instance_variable_get(:@group_by)
  end

  # Data processing tests

  test "processes request data with daily grouping" do
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
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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

  # Time normalization tests

  test "normalizes timestamps correctly for daily grouping" do
    # Create request at specific time within day
    specific_time = 1.day.ago.beginning_of_day + 14.hours + 30.minutes
    create(:chart_request, :at_time, :with_duration,
      at_time: specific_time,
      with_duration: 125
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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
      at_time: specific_time,
      with_duration: 175
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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
      at_time: date,
      with_duration: 175
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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
      at_time: day1,
      with_duration: 100
    )
    create(:chart_request, :at_time, :with_duration,
      at_time: day2,
      with_duration: 200
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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
      at_time: date,
      with_duration: 150
    )

    [ :group_by_hour, :group_by_day ].each do |group_by|
      ransack_query = RailsPulse::Request.ransack({})
      chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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

  # Route parameter tests

  test "works with route parameter present" do
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date,
      with_duration: 250
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: @route
    )

    result = chart.to_rails_chart

    expected_timestamp = date.to_i
    assert_includes result, expected_timestamp
    assert_equal 250.0, result[expected_timestamp][:value]
  end

  test "works with route parameter nil" do
    date = 1.day.ago.beginning_of_day
    create(:chart_request, :at_time, :with_duration,
      at_time: date,
      with_duration: 300
    )

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
      ransack_query: ransack_query,
      route: nil
    )

    result = chart.to_rails_chart

    expected_timestamp = date.to_i
    assert_includes result, expected_timestamp
    assert_equal 300.0, result[expected_timestamp][:value]
  end

  # Performance scenario tests

  test "calculates correct averages for mixed durations" do
    date = 2.days.ago.beginning_of_day
    durations = [ 50, 100, 150, 200, 250 ] # Average should be 150

    durations.each_with_index do |duration, i|
      create(:chart_request, :at_time, :with_duration,
        at_time: date + (i * 2).hours,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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
        at_time: timestamp,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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
        at_time: time,
        with_duration: duration
      )
    end

    ransack_query = RailsPulse::Request.ransack({})
    chart = RailsPulse::Requests::Charts::AverageResponseTimes.new(
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
end
