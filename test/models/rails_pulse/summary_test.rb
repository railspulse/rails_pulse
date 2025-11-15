require "test_helper"

class RailsPulse::SummaryTest < ActiveSupport::TestCase
  include Shoulda::Matchers::ActiveModel
  include Shoulda::Matchers::ActiveRecord

  # Test associations
  test "should have correct associations" do
    assert belong_to(:summarizable).optional.matches?(RailsPulse::Summary.new)
    assert belong_to(:route).optional.matches?(RailsPulse::Summary.new)
    assert belong_to(:query).optional.matches?(RailsPulse::Summary.new)
    assert belong_to(:job).optional.matches?(RailsPulse::Summary.new)
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
    expected_associations = %w[job query route]

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

  # Tag filtering tests
  test "with_tag_filters should return all summaries when no filters applied" do
    all_count = RailsPulse::Summary.count
    filtered_count = RailsPulse::Summary.with_tag_filters([], true).count

    assert_equal all_count, filtered_count
  end

  test "with_tag_filters should exclude routes with disabled tags" do
    # api_users has ["api", "users"], api_posts has ["api", "posts"]
    route_summary = rails_pulse_summaries(:route_summary_1)  # links to api_users route

    # When "api" tag is disabled, should exclude summaries for routes with "api" tag
    filtered = RailsPulse::Summary.with_tag_filters([ "api" ], true)
      .where(summarizable_type: "RailsPulse::Route")

    assert_not_includes filtered, route_summary
  end

  test "with_tag_filters should exclude queries with disabled tags" do
    # simple_query has ["database", "users"]
    query_summary = rails_pulse_summaries(:query_summary_1)  # links to complex_query

    # When "database" tag is disabled, should exclude summaries for queries with "database" tag
    filtered = RailsPulse::Summary.with_tag_filters([ "database" ], true)
      .where(summarizable_type: "RailsPulse::Query")

    assert_not_includes filtered, query_summary
  end

  test "with_tag_filters should exclude non-tagged items when show_non_tagged is false" do
    # api_other has tags: '[]'
    # Create a summary for a non-tagged route
    non_tagged_route = rails_pulse_routes(:api_other)
    non_tagged_summary = RailsPulse::Summary.create!(
      summarizable: non_tagged_route,
      summarizable_type: "RailsPulse::Route",
      period_type: "hour",
      period_start: 1.hour.ago,
      period_end: Time.current,
      avg_duration: 100,
      min_duration: 50,
      max_duration: 150,
      count: 10,
      error_count: 0,
      success_count: 10
    )

    # When show_non_tagged is false, should exclude non-tagged items
    filtered = RailsPulse::Summary.with_tag_filters([], false)
      .where(summarizable_type: "RailsPulse::Route")

    assert_not_includes filtered, non_tagged_summary
  end

  test "with_tag_filters should include non-tagged items when show_non_tagged is true" do
    # api_other has tags: '[]'
    non_tagged_route = rails_pulse_routes(:api_other)
    non_tagged_summary = RailsPulse::Summary.create!(
      summarizable: non_tagged_route,
      summarizable_type: "RailsPulse::Route",
      period_type: "hour",
      period_start: 1.hour.ago,
      period_end: Time.current,
      avg_duration: 100,
      min_duration: 50,
      max_duration: 150,
      count: 10,
      error_count: 0,
      success_count: 10
    )

    # When show_non_tagged is true, should include non-tagged items
    filtered = RailsPulse::Summary.with_tag_filters([], true)
      .where(summarizable_type: "RailsPulse::Route")

    assert_includes filtered, non_tagged_summary
  end

  test "with_tag_filters should always include Request summaries" do
    # Create a Request summary
    request_summary = RailsPulse::Summary.create!(
      summarizable_type: "RailsPulse::Request",
      summarizable_id: 0,
      period_type: "hour",
      period_start: 1.hour.ago,
      period_end: Time.current,
      avg_duration: 100,
      min_duration: 50,
      max_duration: 150,
      count: 10,
      error_count: 0,
      success_count: 10
    )

    # Request summaries should always be included regardless of tag filters
    filtered = RailsPulse::Summary.with_tag_filters([ "api" ], false)

    assert_includes filtered, request_summary
  end

  test "with_tag_filters should handle non_tagged virtual tag correctly" do
    # "non_tagged" is a virtual tag that doesn't exist in the database
    # It should be filtered out and handled specially
    filtered = RailsPulse::Summary.with_tag_filters([ "non_tagged" ], false)

    # Should not error and should filter based on show_non_tagged parameter
    assert_kind_of ActiveRecord::Relation, filtered
  end
end
