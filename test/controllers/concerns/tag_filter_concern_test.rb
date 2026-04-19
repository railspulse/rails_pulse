require "test_helper"

class TagFilterConcernTest < ActionController::TestCase
  class TestController < ActionController::Base
    include TagFilterConcern

    attr_accessor :session

    def initialize
      super
      @session = {}
    end

    def session_disabled_tags
      (session[:global_filters] || {})["disabled_tags"] || []
    end
  end

  fixtures :rails_pulse_routes

  setup do
    @controller = TestController.new
  end

  # apply_tag_filters Tests

  test "apply_tag_filters returns query unchanged when disabled_tags empty" do
    @controller.stubs(:session_disabled_tags).returns([])
    query = RailsPulse::Route.all

    result = @controller.send(:apply_tag_filters, query)

    assert_equal RailsPulse::Route.count, result.count
  end

  test "apply_tag_filters filters routes with single disabled tag" do
    @controller.stubs(:session_disabled_tags).returns([ "api" ])
    @controller.session[:show_non_tagged] = true
    query = RailsPulse::Route.all

    result = @controller.send(:apply_tag_filters, query)

    # Routes with "api" tag should be excluded
    result_ids = result.pluck(:id)

    assert_not_includes result_ids, rails_pulse_routes(:api_users).id
    assert_not_includes result_ids, rails_pulse_routes(:api_posts).id

    # Routes without "api" tag should be included
    assert_includes result_ids, rails_pulse_routes(:api_cleanup).id
  end

  test "apply_tag_filters filters routes with multiple disabled tags" do
    @controller.stubs(:session_disabled_tags).returns([ "api", "maintenance" ])
    @controller.session[:show_non_tagged] = true
    query = RailsPulse::Route.all

    result = @controller.send(:apply_tag_filters, query)

    # Routes with either "api" or "maintenance" should be excluded
    result_ids = result.pluck(:id)

    assert_not_includes result_ids, rails_pulse_routes(:api_users).id
    assert_not_includes result_ids, rails_pulse_routes(:api_posts).id
    assert_not_includes result_ids, rails_pulse_routes(:api_cleanup).id
  end

  test "apply_tag_filters chains without_tag for each disabled tag" do
    @controller.stubs(:session_disabled_tags).returns([ "users" ])
    @controller.session[:show_non_tagged] = true
    query = RailsPulse::Route.all

    result = @controller.send(:apply_tag_filters, query)

    # api_users has "users" tag, should be excluded
    result_ids = result.pluck(:id)

    assert_not_includes result_ids, rails_pulse_routes(:api_users).id

    # Others without "users" tag should be included
    assert_includes result_ids, rails_pulse_routes(:api_posts).id
  end

  test "apply_tag_filters calls apply_non_tagged_filter" do
    @controller.stubs(:session_disabled_tags).returns([])
    @controller.session[:show_non_tagged] = false
    query = RailsPulse::Route.all

    result = @controller.send(:apply_tag_filters, query)

    # Should only include routes with tags
    result_ids = result.pluck(:id)

    assert_not_includes result_ids, rails_pulse_routes(:api_other).id  # No tags
    assert_includes result_ids, rails_pulse_routes(:api_users).id  # Has tags
  end

  test "apply_tag_filters gets disabled tags from session_disabled_tags helper" do
    @controller.session[:global_filters] = { "disabled_tags" => [ "api" ] }
    @controller.session[:show_non_tagged] = true
    query = RailsPulse::Route.all

    result = @controller.send(:apply_tag_filters, query)

    # Should exclude routes with "api" tag
    result_ids = result.pluck(:id)

    assert_not_includes result_ids, rails_pulse_routes(:api_users).id
  end

  # apply_non_tagged_filter Tests

  test "apply_non_tagged_filter returns query unchanged when show_non_tagged is true" do
    @controller.session[:show_non_tagged] = true
    query = RailsPulse::Route.all

    result = @controller.send(:apply_non_tagged_filter, query)

    assert_equal RailsPulse::Route.count, result.count
  end

  test "apply_non_tagged_filter returns query unchanged when show_non_tagged is nil" do
    @controller.session[:show_non_tagged] = nil
    query = RailsPulse::Route.all

    result = @controller.send(:apply_non_tagged_filter, query)

    # Nil defaults to true (show non-tagged)
    assert_equal RailsPulse::Route.count, result.count
  end

  test "apply_non_tagged_filter filters to only tagged routes when show_non_tagged false" do
    @controller.session[:show_non_tagged] = false
    query = RailsPulse::Route.all

    result = @controller.send(:apply_non_tagged_filter, query)

    # Should only include routes with tags
    result_ids = result.pluck(:id)

    assert_not_includes result_ids, rails_pulse_routes(:api_other).id  # No tags
    assert_includes result_ids, rails_pulse_routes(:api_users).id  # Has tags
    assert_includes result_ids, rails_pulse_routes(:api_cleanup).id  # Has tags
  end

  test "apply_non_tagged_filter checks session directly" do
    # Don't set show_non_tagged, should default to showing all
    query = RailsPulse::Route.all

    result = @controller.send(:apply_non_tagged_filter, query)

    assert_equal RailsPulse::Route.count, result.count
  end

  # Integration Tests

  test "apply_tag_filters chains both disabled tags and non_tagged filters" do
    @controller.stubs(:session_disabled_tags).returns([ "api" ])
    @controller.session[:show_non_tagged] = false
    query = RailsPulse::Route.all

    result = @controller.send(:apply_tag_filters, query)

    # Should exclude routes with "api" tag AND routes with no tags
    result_ids = result.pluck(:id)

    assert_not_includes result_ids, rails_pulse_routes(:api_users).id  # Has "api" tag
    assert_not_includes result_ids, rails_pulse_routes(:api_posts).id  # Has "api" tag
    assert_not_includes result_ids, rails_pulse_routes(:api_other).id  # No tags
    assert_includes result_ids, rails_pulse_routes(:api_cleanup).id  # Has "maintenance" tag
  end

  test "apply_tag_filters with multiple disabled tags and show_non_tagged false" do
    @controller.stubs(:session_disabled_tags).returns([ "posts", "maintenance" ])
    @controller.session[:show_non_tagged] = false
    query = RailsPulse::Route.all

    result = @controller.send(:apply_tag_filters, query)

    # Should exclude routes with "posts" or "maintenance" tags AND routes with no tags
    result_ids = result.pluck(:id)

    assert_not_includes result_ids, rails_pulse_routes(:api_posts).id  # Has "posts" tag
    assert_not_includes result_ids, rails_pulse_routes(:api_cleanup).id  # Has "maintenance" tag
    assert_not_includes result_ids, rails_pulse_routes(:api_other).id  # No tags
    assert_includes result_ids, rails_pulse_routes(:api_users).id  # Has only "users" and "api" tags
  end

  test "apply_tag_filters with real fixture routes with various tag combinations" do
    # Test all fixtures have expected tags
    api_users = rails_pulse_routes(:api_users)
    api_posts = rails_pulse_routes(:api_posts)
    api_cleanup = rails_pulse_routes(:api_cleanup)
    api_other = rails_pulse_routes(:api_other)

    # Verify fixture tags
    assert_includes JSON.parse(api_users.tags), "api"
    assert_includes JSON.parse(api_users.tags), "users"
    assert_includes JSON.parse(api_posts.tags), "api"
    assert_includes JSON.parse(api_posts.tags), "posts"
    assert_includes JSON.parse(api_cleanup.tags), "maintenance"
    assert_empty JSON.parse(api_other.tags)

    # Test filtering works with these real fixtures
    @controller.stubs(:session_disabled_tags).returns([ "users" ])
    @controller.session[:show_non_tagged] = true
    query = RailsPulse::Route.all

    result = @controller.send(:apply_tag_filters, query)

    result_ids = result.pluck(:id)

    assert_not_includes result_ids, api_users.id  # Has "users" tag
    assert_includes result_ids, api_posts.id  # No "users" tag
    assert_includes result_ids, api_cleanup.id  # No "users" tag
    assert_includes result_ids, api_other.id  # No "users" tag
  end
end
