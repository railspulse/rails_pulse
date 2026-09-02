require "test_helper"

class RailsPulse::TaggableTest < ActiveSupport::TestCase
  setup do
    @exact    = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/taggable_test/exact",    tags: '["api"]')
    @extended = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/taggable_test/extended", tags: '["api_internal"]')
    @untagged = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/taggable_test/untagged", tags: "[]")
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

  # SQLite has no default LIKE escape character, so `_` in a tag was a wildcard
  # (and the escaped `\_` a literal backslash) until the ESCAPE clause was made
  # explicit. Both cases must behave identically on every adapter.
  test "with_tag matches an underscore literally" do
    underscored = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/taggable_test/underscored", tags: '["team_a"]')
    lookalike   = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/taggable_test/lookalike",  tags: '["teamxa"]')

    results = RailsPulse::Route.with_tag("team_a")

    assert_includes results, underscored
    assert_not_includes results, lookalike
  end

  test "without_tag excludes an underscored tag literally" do
    underscored = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/taggable_test/underscored", tags: '["team_a"]')
    lookalike   = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/taggable_test/lookalike",  tags: '["teamxa"]')

    results = RailsPulse::Route.without_tag("team_a")

    assert_not_includes results, underscored
    assert_includes results, lookalike
  end

  test "with_tag treats a percent sign literally" do
    assert_empty RailsPulse::Route.with_tag("%")
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

  # with_tags

  test "with_tags returns records that have any tags" do
    results = RailsPulse::Route.with_tags

    assert_includes results, @exact
    assert_includes results, @extended
  end

  test "with_tags excludes records with no tags" do
    results = RailsPulse::Route.with_tags

    assert_not_includes results, @untagged
  end

  test "with_tags excludes records with empty array" do
    empty_array_route = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/empty", tags: "[]")
    results = RailsPulse::Route.with_tags

    assert_not_includes results, empty_array_route
  end

  # tag_list

  test "tag_list returns array of tags" do
    assert_equal [ "api" ], @exact.tag_list
    assert_equal [ "api_internal" ], @extended.tag_list
  end

  test "tag_list returns empty array for untagged record" do
    assert_empty @untagged.tag_list
  end

  test "tag_list returns empty array for nil tags" do
    route = RailsPulse::Route.new(http_methods: '["GET"]', path: "/nil_tags")
    route.tags = nil

    assert_empty route.tag_list
  end

  test "tag_list handles malformed JSON gracefully" do
    route = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/malformed")
    route.update_column(:tags, "invalid json")

    assert_empty route.tag_list
  end

  # tag_list=

  test "tag_list= sets tags from array" do
    @untagged.tag_list = [ "test", "demo" ]

    assert_equal [ "test", "demo" ], @untagged.tag_list
    assert_equal [ "test", "demo" ], JSON.parse(@untagged.tags)
  end

  test "tag_list= converts to JSON string" do
    @untagged.tag_list = [ "api" ]

    assert_kind_of String, @untagged.tags
    assert_equal [ "api" ], JSON.parse(@untagged.tags)
  end

  # add_tag

  test "add_tag adds new tag successfully" do
    result = @untagged.add_tag("test")

    assert result
    assert_includes @untagged.tag_list, "test"
  end

  test "add_tag persists to database" do
    @untagged.add_tag("persistent")
    @untagged.reload

    assert_includes @untagged.tag_list, "persistent"
  end

  test "add_tag returns true when tag already exists" do
    result = @exact.add_tag("api")

    assert result
    assert_equal 1, @exact.tag_list.count("api")
  end

  test "add_tag returns false for blank tag" do
    result = @untagged.add_tag("")

    refute result
  end

  test "add_tag returns false for nil tag" do
    result = @untagged.add_tag(nil)

    refute result
  end

  test "add_tag returns false for tag exceeding max length" do
    long_tag = "a" * 51
    result = @untagged.add_tag(long_tag)

    refute result
  end

  test "add_tag accepts tag at max length" do
    max_tag = "a" * 50
    result = @untagged.add_tag(max_tag)

    assert result
  end

  test "add_tag returns false for invalid characters" do
    invalid_tags = [ "tag with spaces", "tag@special", "tag#hash", "tag!exclaim" ]

    invalid_tags.each do |tag|
      result = @untagged.add_tag(tag)

      refute result, "Should reject tag: #{tag}"
    end
  end

  test "add_tag accepts valid alphanumeric, hyphen, and underscore" do
    valid_tags = [ "api", "api-v2", "api_internal", "test123", "TEST" ]

    valid_tags.each do |tag|
      route = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/test_#{tag}")
      result = route.add_tag(tag)

      assert result, "Should accept tag: #{tag}"
    end
  end

  # remove_tag

  test "remove_tag removes existing tag" do
    result = @exact.remove_tag("api")

    assert result
    assert_not_includes @exact.tag_list, "api"
  end

  test "remove_tag persists to database" do
    @exact.remove_tag("api")
    @exact.reload

    assert_not_includes @exact.tag_list, "api"
  end

  test "remove_tag returns nil when tag does not exist" do
    result = @untagged.remove_tag("nonexistent")

    assert_nil result
  end

  test "remove_tag handles string and symbol" do
    @exact.add_tag("symbol_test")
    @exact.remove_tag(:symbol_test)

    assert_not_includes @exact.tag_list, "symbol_test"
  end

  # ensure_tags_is_array callback

  test "ensure_tags_is_array converts nil to empty array on save" do
    route = RailsPulse::Route.new(http_methods: '["GET"]', path: "/callback_test")
    route.tags = nil
    route.save!

    assert_equal "[]", route.tags
  end

  test "ensure_tags_is_array converts array to JSON on save" do
    route = RailsPulse::Route.new(http_methods: '["GET"]', path: "/callback_array")
    route.tags = [ "test", "demo" ]
    route.save!

    assert_equal [ "test", "demo" ], JSON.parse(route.tags)
  end

  test "ensure_tags_is_array leaves valid JSON string unchanged" do
    route = RailsPulse::Route.new(http_methods: '["GET"]', path: "/callback_json")
    route.tags = '["already_json"]'
    route.save!

    assert_equal [ "already_json" ], JSON.parse(route.tags)
  end
end
