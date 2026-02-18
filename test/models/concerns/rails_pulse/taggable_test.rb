require "test_helper"

class RailsPulse::TaggableTest < ActiveSupport::TestCase
  setup do
    @exact    = RailsPulse::Route.create!(method: "GET", path: "/taggable_test/exact",    tags: '["api"]')
    @extended = RailsPulse::Route.create!(method: "GET", path: "/taggable_test/extended", tags: '["api_internal"]')
    @untagged = RailsPulse::Route.create!(method: "GET", path: "/taggable_test/untagged", tags: "[]")
  end

  # with_tag

  test "with_tag returns records that have the exact tag" do
    assert_includes RailsPulse::Route.with_tag("api"), @exact
  end

  test "with_tag does not return records whose tag contains the search term as a substring" do
    assert_not_includes RailsPulse::Route.with_tag("api"), @extended
  end

  test "with_tag does not return untagged records" do
    assert_not_includes RailsPulse::Route.with_tag("api"), @untagged
  end

  # without_tag

  test "without_tag excludes records that have the exact tag" do
    assert_not_includes RailsPulse::Route.without_tag("api"), @exact
  end

  test "without_tag includes records whose tag contains the search term as a substring" do
    assert_includes RailsPulse::Route.without_tag("api"), @extended
  end

  test "without_tag includes untagged records" do
    assert_includes RailsPulse::Route.without_tag("api"), @untagged
  end

  # has_tag? — Ruby-side check, unaffected by the LIKE bug

  test "has_tag? returns true for an exact matching tag" do
    assert @exact.has_tag?("api")
  end

  test "has_tag? returns false when the tag name only appears as a substring of another tag" do
    refute @extended.has_tag?("api")
  end
end
