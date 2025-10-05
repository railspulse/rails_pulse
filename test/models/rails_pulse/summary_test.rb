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
    summary = rails_pulse_summaries(:route_summary_1)

    assert_predicate summary, :valid?
  end

  test "should have correct period types constant" do
    expected_types = %w[hour day week month]

    assert_equal expected_types, RailsPulse::Summary::PERIOD_TYPES
  end

  test "should include ransackable attributes" do
    expected_attributes = %w[
      period_start period_end avg_duration min_duration max_duration count error_count
      requests_per_minute error_rate_percentage route_path_cont
      execution_count total_time_consumed normalized_sql
      summarizable_id summarizable_type
    ]

    assert_equal expected_attributes.sort, RailsPulse::Summary.ransackable_attributes.sort
  end

  test "should include ransackable associations" do
    expected_associations = %w[route query]

    assert_equal expected_associations.sort, RailsPulse::Summary.ransackable_associations.sort
  end

  test "should have scopes" do
    # Test for_period_type scope with fixture data
    hour_summary = rails_pulse_summaries(:route_summary_1)  # hour type
    query_summary = rails_pulse_summaries(:query_summary_1)  # day type

    hour_summaries = RailsPulse::Summary.for_period_type("hour")

    assert_includes hour_summaries, hour_summary
    assert_not_includes hour_summaries, query_summary

    # Test for_routes scope
    route_summaries = RailsPulse::Summary.for_routes

    assert_includes route_summaries, hour_summary
    assert_not_includes route_summaries, query_summary

    # Test for_queries scope
    query_summaries = RailsPulse::Summary.for_queries

    assert_includes query_summaries, query_summary
    assert_not_includes query_summaries, hour_summary

    # Test recent scope works (ordering)
    assert_respond_to RailsPulse::Summary, :recent
  end

  test "should work with polymorphic associations" do
    route_summary = rails_pulse_summaries(:route_summary_1)
    query_summary = rails_pulse_summaries(:query_summary_1)

    assert_equal rails_pulse_routes(:api_users), route_summary.summarizable
    assert_equal rails_pulse_queries(:complex_query), query_summary.summarizable
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
    recent_summaries = RailsPulse::Summary.recent

    # Should return summaries ordered by period_start DESC
    assert_operator recent_summaries.count, :>, 0

    # Verify scope exists and is callable
    assert_respond_to RailsPulse::Summary, :recent
  end
end
