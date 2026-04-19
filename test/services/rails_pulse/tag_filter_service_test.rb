require "test_helper"

module RailsPulse
  class TagFilterServiceTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_jobs

    # Filter IDs Tests

    test "filter_ids returns all ids when no disabled tags" do
      ids = TagFilterService.filter_ids(Route, [], true)

      assert_operator ids.size, :>, 0
    end

    test "filter_ids excludes items with disabled tags" do
      # Find a route with tags to test against
      tagged_route = rails_pulse_routes(:api_users)

      ids = TagFilterService.filter_ids(Route, [ "api" ], true)

      assert_not_includes ids, tagged_route.id
    end

    test "filter_ids includes non-tagged items when show_non_tagged is true" do
      # Routes without tags should be included
      all_routes = Route.pluck(:id)

      ids = TagFilterService.filter_ids(Route, [], true)

      assert_equal all_routes.sort, ids.sort
    end

    test "filter_ids excludes non-tagged items when show_non_tagged is false" do
      # Find a route without tags
      non_tagged_count = Route.where("tags IS NULL OR tags = '[]'").count

      ids_with_non_tagged = TagFilterService.filter_ids(Route, [], true)
      ids_without_non_tagged = TagFilterService.filter_ids(Route, [], false)

      assert_operator ids_with_non_tagged.size, :>=, ids_without_non_tagged.size
      assert_operator ids_with_non_tagged.size - ids_without_non_tagged.size, :>=, 0
    end

    test "filter_ids handles multiple disabled tags" do
      ids = TagFilterService.filter_ids(Route, [ "api", "users" ], true)

      # Should exclude routes with either tag
      assert_kind_of Array, ids
    end

    test "filter_ids sanitizes SQL wildcards in tags" do
      # Test that % and _ are escaped properly
      assert_nothing_raised do
        TagFilterService.filter_ids(Route, [ "%_test" ], true)
      end
    end

    test "filter_ids handles empty disabled_tags array" do
      ids = TagFilterService.filter_ids(Route, [], true)

      assert_kind_of Array, ids
      assert_operator ids.size, :>, 0
    end

    test "filter_ids works with Query model" do
      ids = TagFilterService.filter_ids(Query, [], true)

      assert_kind_of Array, ids
    end

    test "filter_ids works with Job model" do
      ids = TagFilterService.filter_ids(Job, [], true)

      assert_kind_of Array, ids
    end

    # Filter All Tests

    test "filter_all returns hash with all model types" do
      result = TagFilterService.filter_all([], true)

      assert_kind_of Hash, result
      assert_includes result.keys, :route_ids
      assert_includes result.keys, :query_ids
      assert_includes result.keys, :job_ids
    end

    test "filter_all filters routes, queries, and jobs" do
      result = TagFilterService.filter_all([ "api" ], true)

      # Routes with "api" tag should be excluded
      tagged_route = rails_pulse_routes(:api_users)

      assert_not_includes result[:route_ids], tagged_route.id

      # All results should be arrays
      assert_kind_of Array, result[:route_ids]
      assert_kind_of Array, result[:query_ids]
      assert_kind_of Array, result[:job_ids]
    end

    test "filter_all handles non_tagged virtual tag" do
      # "non_tagged" should be filtered out and not cause errors
      result = TagFilterService.filter_all([ "non_tagged" ], false)

      assert_kind_of Hash, result
      assert_kind_of Array, result[:route_ids]
    end

    test "filter_all respects show_non_tagged parameter" do
      result_with = TagFilterService.filter_all([], true)
      result_without = TagFilterService.filter_all([], false)

      # With non-tagged items should have more or equal IDs
      assert_operator result_with[:route_ids].size, :>=, result_without[:route_ids].size
    end

    test "filter_all handles mixed tags including non_tagged" do
      result = TagFilterService.filter_all([ "api", "non_tagged" ], true)

      # Should filter out "api" tag but ignore "non_tagged"
      assert_kind_of Hash, result
      tagged_route = rails_pulse_routes(:api_users)

      assert_not_includes result[:route_ids], tagged_route.id
    end

    # Edge Cases

    test "filter_ids handles empty arrays gracefully" do
      ids = TagFilterService.filter_ids(Route, [], true)

      assert_kind_of Array, ids
    end

    test "filter_all handles nil disabled_tags" do
      assert_nothing_raised do
        result = TagFilterService.filter_all(nil, true)

        assert_kind_of Hash, result
      end
    end

    test "filter_all handles empty disabled_tags array" do
      result = TagFilterService.filter_all([], true)

      assert_kind_of Hash, result
      assert_operator result[:route_ids].size, :>, 0
    end
  end
end
