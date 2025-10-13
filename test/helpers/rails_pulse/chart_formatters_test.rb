require "test_helper"

class RailsPulse::ChartFormattersTest < ActiveSupport::TestCase
  test "period_as_time_or_date returns time formatter for recent data" do
    formatter = RailsPulse::ChartFormatters.period_as_time_or_date(24)

    assert_includes formatter, "function(value)"
    assert_includes formatter, "getHours()"
    assert_includes formatter, "padStart(2, '0')"
    assert_includes formatter, ":00"
  end

  test "period_as_time_or_date returns date formatter for older data" do
    formatter = RailsPulse::ChartFormatters.period_as_time_or_date(26)

    assert_includes formatter, "function(value)"
    assert_includes formatter, "toLocaleDateString"
    assert_includes formatter, "month: 'short'"
    assert_includes formatter, "day: 'numeric'"
  end

  test "period_as_time_or_date boundary condition at 25 hours" do
    time_formatter = RailsPulse::ChartFormatters.period_as_time_or_date(25)
    date_formatter = RailsPulse::ChartFormatters.period_as_time_or_date(26)

    assert_includes time_formatter, "getHours()"
    assert_includes date_formatter, "toLocaleDateString"
  end

  test "tooltip_as_time_or_date_with_marker returns date formatter for older data" do
    formatter = RailsPulse::ChartFormatters.tooltip_as_time_or_date_with_marker(26)

    assert_includes formatter, "function(params)"
    assert_includes formatter, "toLocaleDateString"
    assert_includes formatter, "month: 'short'"
    assert_includes formatter, "day: 'numeric'"
    assert_includes formatter, "data.marker"
    assert_includes formatter, "parseInt(data.data)"
    assert_includes formatter, "ms"
  end

  test "tooltip_as_time_or_date_with_marker boundary condition at 25 hours" do
    time_formatter = RailsPulse::ChartFormatters.tooltip_as_time_or_date_with_marker(25)
    date_formatter = RailsPulse::ChartFormatters.tooltip_as_time_or_date_with_marker(26)

    assert_includes time_formatter, "getHours()"
    assert_includes date_formatter, "toLocaleDateString"
  end

  test "formatters generate valid JavaScript" do
    time_formatter = RailsPulse::ChartFormatters.period_as_time_or_date(24)
    tooltip_formatter = RailsPulse::ChartFormatters.tooltip_as_time_or_date_with_marker(24)

    # Basic JavaScript syntax validation
    assert_includes time_formatter, "function"
    assert_includes time_formatter, "return"
    assert_includes tooltip_formatter, "function"
    assert_includes tooltip_formatter, "return"
  end

  test "formatters handle edge cases" do
    # Test with 0 hours
    formatter = RailsPulse::ChartFormatters.period_as_time_or_date(0)

    assert_includes formatter, "getHours()"

    # Test with very large number
    formatter = RailsPulse::ChartFormatters.period_as_time_or_date(1000)

    assert_includes formatter, "toLocaleDateString"
  end
end
