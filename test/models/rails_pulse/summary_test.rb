require "test_helper"

class RailsPulse::SummaryTest < ActiveSupport::TestCase
  include Shoulda::Matchers::ActiveModel
  include Shoulda::Matchers::ActiveRecord

  # Test associations
  test "should have correct associations" do
    assert belong_to(:summarizable).optional.matches?(RailsPulse::Summary.new)
    assert belong_to(:route).optional.matches?(RailsPulse::Summary.new)
    assert belong_to(:query).optional.matches?(RailsPulse::Summary.new)
  end

  # Test validations
  test "should have correct validations" do
    summary = RailsPulse::Summary.new

    # Inclusion validation
    assert validate_inclusion_of(:period_type).in_array(RailsPulse::Summary::PERIOD_TYPES).matches?(summary)

    # Presence validations
    assert validate_presence_of(:period_start).matches?(summary)
    assert validate_presence_of(:period_end).matches?(summary)
  end

  test "should be valid with required attributes" do
    summary = create(:summary)
    assert summary.valid?
  end

  test "should have correct period types constant" do
    expected_types = %w[hour day week month]
    assert_equal expected_types, RailsPulse::Summary::PERIOD_TYPES
  end

  test "should include ransackable attributes" do
    expected_attributes = %w[
      period_start period_end avg_duration max_duration count error_count
      requests_per_minute error_rate_percentage route_path_cont
      execution_count total_time_consumed normalized_sql
    ]
    assert_equal expected_attributes.sort, RailsPulse::Summary.ransackable_attributes.sort
  end

  test "should include ransackable associations" do
    expected_associations = %w[route query]
    assert_equal expected_associations.sort, RailsPulse::Summary.ransackable_associations.sort
  end

  test "should have scopes" do
    # Test for_period_type scope
    hour_summary = create(:summary, period_type: "hour")
    day_summary = create(:summary, period_type: "day")

    hour_summaries = RailsPulse::Summary.for_period_type("hour")
    assert_includes hour_summaries, hour_summary
    assert_not_includes hour_summaries, day_summary

    # Test for_date_range scope
    start_date = 1.day.ago.beginning_of_day
    end_date = Time.current.end_of_day

    recent_summary = create(:summary, period_start: Time.current.beginning_of_hour)
    old_summary = create(:summary, period_start: 2.days.ago.beginning_of_hour)

    range_summaries = RailsPulse::Summary.for_date_range(start_date, end_date)
    assert_includes range_summaries, recent_summary
    assert_not_includes range_summaries, old_summary

    # Test for_requests scope
    request_summary = create(:summary, summarizable_type: "RailsPulse::Request")
    route_summary = create(:summary, summarizable_type: "RailsPulse::Route")

    request_summaries = RailsPulse::Summary.for_requests
    assert_includes request_summaries, request_summary
    assert_not_includes request_summaries, route_summary

    # Test for_routes scope
    route_summaries = RailsPulse::Summary.for_routes
    assert_includes route_summaries, route_summary
    assert_not_includes route_summaries, request_summary

    # Test for_queries scope
    query_summary = create(:summary, summarizable_type: "RailsPulse::Query")
    query_summaries = RailsPulse::Summary.for_queries
    assert_includes query_summaries, query_summary
    assert_not_includes query_summaries, route_summary

    # Test overall_requests scope
    overall_summary = create(:summary, summarizable_type: "RailsPulse::Request", summarizable_id: 0)
    specific_summary = create(:summary, summarizable_type: "RailsPulse::Request", summarizable_id: 1)

    overall_summaries = RailsPulse::Summary.overall_requests
    assert_includes overall_summaries, overall_summary
    assert_not_includes overall_summaries, specific_summary
  end

  test "should work with polymorphic associations" do
    route = create(:route)
    query = create(:query)

    route_summary = create(:summary, summarizable: route)
    query_summary = create(:summary, summarizable: query)

    assert_equal route, route_summary.summarizable
    assert_equal query, query_summary.summarizable
    assert_equal "RailsPulse::Route", route_summary.summarizable_type
    assert_equal "RailsPulse::Query", query_summary.summarizable_type
  end

  test "should calculate period end correctly" do
    time = Time.parse("2024-01-15 14:30:00 UTC")

    assert_equal time.end_of_hour, RailsPulse::Summary.calculate_period_end("hour", time)
    assert_equal time.end_of_day, RailsPulse::Summary.calculate_period_end("day", time)
    assert_equal time.end_of_week, RailsPulse::Summary.calculate_period_end("week", time)
    assert_equal time.end_of_month, RailsPulse::Summary.calculate_period_end("month", time)
  end

  test "should normalize period start correctly" do
    time = Time.parse("2024-01-15 14:30:00 UTC")

    assert_equal time.beginning_of_hour, RailsPulse::Summary.normalize_period_start("hour", time)
    assert_equal time.beginning_of_day, RailsPulse::Summary.normalize_period_start("day", time)
    assert_equal time.beginning_of_week, RailsPulse::Summary.normalize_period_start("week", time)
    assert_equal time.beginning_of_month, RailsPulse::Summary.normalize_period_start("month", time)
  end

  test "should order by recent scope" do
    old_summary = create(:summary, period_start: 2.hours.ago)
    new_summary = create(:summary, period_start: 1.hour.ago)

    recent_summaries = RailsPulse::Summary.recent
    assert_equal [ new_summary, old_summary ], recent_summaries.to_a
  end
end
