require "test_helper"

class RailsPulse::FormattingHelperTest < ActionView::TestCase
  include RailsPulse::FormattingHelper

  test "human_readable_occurred_at formats Time object" do
    time = Time.new(2024, 1, 15, 14, 30, 0)
    result = human_readable_occurred_at(time)

    assert_equal "Jan 15, 2024  2:30 PM", result
  end

  test "human_readable_occurred_at formats DateTime object" do
    # Create a specific time in UTC then convert to local for predictable testing
    utc_time = Time.utc(2024, 1, 15, 14, 30, 0)
    local_time = utc_time.getlocal
    result = human_readable_occurred_at(local_time)
    expected_result = local_time.strftime("%b %d, %Y %l:%M %p")

    assert_equal expected_result, result
  end

  test "human_readable_occurred_at formats string" do
    time_string = "2024-01-15 14:30:00"
    result = human_readable_occurred_at(time_string)

    assert_equal "Jan 15, 2024  2:30 PM", result
  end

  test "human_readable_occurred_at handles nil" do
    result = human_readable_occurred_at(nil)

    assert_equal "", result
  end

  test "human_readable_occurred_at handles empty string" do
    result = human_readable_occurred_at("")

    assert_equal "", result
  end

  test "human_readable_occurred_at handles blank string" do
    result = human_readable_occurred_at("   ")

    assert_equal "", result
  end

  test "human_readable_occurred_at formats different times" do
    # Morning time
    morning = Time.new(2024, 1, 15, 9, 15, 0)
    result = human_readable_occurred_at(morning)

    assert_equal "Jan 15, 2024  9:15 AM", result

    # Evening time
    evening = Time.new(2024, 1, 15, 23, 45, 0)
    result = human_readable_occurred_at(evening)

    assert_equal "Jan 15, 2024 11:45 PM", result

    # Midnight
    midnight = Time.new(2024, 1, 15, 0, 0, 0)
    result = human_readable_occurred_at(midnight)

    assert_equal "Jan 15, 2024 12:00 AM", result
  end

  test "human_readable_occurred_at handles different dates" do
    # Different month
    feb_date = Time.new(2024, 2, 29, 14, 30, 0)
    result = human_readable_occurred_at(feb_date)

    assert_equal "Feb 29, 2024  2:30 PM", result

    # Different year
    old_date = Time.new(2020, 12, 31, 23, 59, 0)
    result = human_readable_occurred_at(old_date)

    assert_equal "Dec 31, 2020 11:59 PM", result
  end

  test "human_readable_occurred_at handles invalid string gracefully" do
    # This should raise an error when parsed, but we're testing the error handling
    assert_raises(ArgumentError) do
      human_readable_occurred_at("invalid-date")
    end
  end
end
