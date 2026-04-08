require "test_helper"

class RailsPulse::TagsHelperTest < ActionView::TestCase
  include RailsPulse::TagsHelper
  include RailsPulse::ApplicationHelper
  include RailsPulse::Engine.routes.url_helpers
  fixtures :rails_pulse_routes, :rails_pulse_queries

  # ============================================================================
  # render_tag_badge Tests
  # ============================================================================

  test "render_tag_badge renders default badge" do
    html = render_tag_badge("production")

    assert_includes html, "<span"
    assert_includes html, "production"
    assert_includes html, "badge font-normal"
    refute_includes html, "badge--secondary"
    refute_includes html, "badge--positive"
  end

  test "render_tag_badge renders secondary variant" do
    html = render_tag_badge("staging", variant: :secondary)

    assert_includes html, "badge badge--secondary font-normal"
    assert_includes html, "staging"
  end

  test "render_tag_badge renders positive variant" do
    html = render_tag_badge("success", variant: :positive)

    assert_includes html, "badge badge--positive font-normal"
    assert_includes html, "success"
  end

  test "render_tag_badge with removable creates button" do
    # Now with route helpers included, this should work
    html = render_tag_badge("production", removable: true, taggable_type: "route", taggable_id: 1)

    assert_includes html, "Production"  # Humanized
    assert_includes html, "tag-remove"
    assert_includes html, "button"
    assert_includes html, "×"
    assert_includes html, "data-turbo-frame=\"_top\""
  end

  test "render_tag_badge removable without taggable info renders simple badge" do
    html = render_tag_badge("production", removable: true)

    # Should render simple badge when taggable_type or taggable_id is missing
    assert_includes html, "production"
    refute_includes html, "button"
    refute_includes html, "×"
  end

  test "render_tag_badge removable with only taggable_type renders simple badge" do
    html = render_tag_badge("production", removable: true, taggable_type: "route")

    assert_includes html, "production"
    refute_includes html, "button"
  end

  test "render_tag_badge removable with only taggable_id renders simple badge" do
    html = render_tag_badge("production", removable: true, taggable_id: 1)

    assert_includes html, "production"
    refute_includes html, "button"
  end

  test "render_tag_badge humanizes tag name" do
    # Testing humanization with removable badge
    html = render_tag_badge("slow_query", removable: true, taggable_type: "query", taggable_id: 1)

    assert_includes html, "Slow query"  # Humanized
    assert_includes html, "badge"
  end

  test "render_tag_badge handles simple tag without humanization" do
    # Simple non-removable badge doesn't humanize
    html = render_tag_badge("slow_query")

    assert_includes html, "slow_query"
    assert_includes html, "badge"
  end

  test "render_tag_badge handles tags with underscores" do
    html = render_tag_badge("high_priority")

    assert_includes html, "high_priority"
  end

  test "render_tag_badge handles empty tag" do
    html = render_tag_badge("")

    assert_includes html, "<span"
    assert_includes html, "badge"
  end

  # ============================================================================
  # display_tag_badges Tests - Array Input
  # ============================================================================

  test "display_tag_badges handles array of tags" do
    html = display_tag_badges([ "production", "urgent", "api" ])

    assert_includes html, "Production"
    assert_includes html, "Urgent"
    assert_includes html, "Api"
    assert_includes html, "badge"
  end

  test "display_tag_badges handles single tag in array" do
    html = display_tag_badges([ "production" ])

    assert_includes html, "Production"
    assert_includes html, "badge"
  end

  test "display_tag_badges handles empty array" do
    html = display_tag_badges([])

    assert_includes html, "-"
    assert_includes html, "text-subtle"
    refute_includes html, "badge"
  end

  # ============================================================================
  # display_tag_badges Tests - JSON String Input
  # ============================================================================

  test "display_tag_badges parses JSON string array" do
    json_string = '["production","staging","development"]'
    html = display_tag_badges(json_string)

    assert_includes html, "Production"
    assert_includes html, "Staging"
    assert_includes html, "Development"
  end

  test "display_tag_badges parses empty JSON array" do
    json_string = '[]'
    html = display_tag_badges(json_string)

    assert_includes html, "-"
    assert_includes html, "text-subtle"
  end

  test "display_tag_badges handles invalid JSON gracefully" do
    invalid_json = "not-valid-json"
    html = display_tag_badges(invalid_json)

    assert_includes html, "-"
    assert_includes html, "text-subtle"
  end

  test "display_tag_badges handles malformed JSON" do
    malformed_json = '["production", "staging"'  # Missing closing bracket
    html = display_tag_badges(malformed_json)

    assert_includes html, "-"
    assert_includes html, "text-subtle"
  end

  # ============================================================================
  # display_tag_badges Tests - Taggable Object Input
  # ============================================================================

  test "display_tag_badges handles taggable object with tag_list" do
    taggable = Struct.new(:tag_list).new([ "slow", "error" ])
    html = display_tag_badges(taggable)

    assert_includes html, "Slow"
    assert_includes html, "Error"
  end

  test "display_tag_badges handles taggable object with empty tag_list" do
    taggable = Struct.new(:tag_list).new([])
    html = display_tag_badges(taggable)

    assert_includes html, "-"
    assert_includes html, "text-subtle"
  end

  test "display_tag_badges handles object without tag_list method" do
    plain_object = Object.new
    html = display_tag_badges(plain_object)

    assert_includes html, "-"
    assert_includes html, "text-subtle"
  end

  # ============================================================================
  # display_tag_badges Tests - Edge Cases
  # ============================================================================

  test "display_tag_badges handles nil input" do
    html = display_tag_badges(nil)

    assert_includes html, "-"
    assert_includes html, "text-subtle"
  end

  test "display_tag_badges humanizes tag names" do
    html = display_tag_badges([ "high_priority", "needs_review" ])

    assert_includes html, "High priority"
    assert_includes html, "Needs review"
  end

  test "display_tag_badges separates tags with spaces" do
    html = display_tag_badges([ "tag1", "tag2", "tag3" ])

    # Should use safe_join with " " separator
    assert_includes html, "</div> <div"
  end

  test "display_tag_badges renders each tag as a div with badge class" do
    html = display_tag_badges([ "test" ])

    assert_includes html, "<div"
    assert_includes html, "class=\"badge\""
    assert_includes html, "Test"
    assert_includes html, "</div>"
  end

  test "display_tag_badges handles special characters in tags" do
    html = display_tag_badges([ "tag-with-dash", "tag.with.dot" ])

    # Humanize converts dashes and dots, but may not add spaces
    assert_includes html, "badge"
    assert_kind_of String, html
  end

  test "display_tag_badges handles numeric tags" do
    html = display_tag_badges([ "v1", "v2", "v3" ])

    assert_includes html, "V1"
    assert_includes html, "V2"
    assert_includes html, "V3"
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  test "render_tag_badge and display_tag_badges work together" do
    # Test that both methods can be used in the same context
    badge1 = render_tag_badge("production", variant: :positive)
    badges2 = display_tag_badges([ "staging", "development" ])

    assert_includes badge1, "badge badge--positive"
    assert_includes badges2, "Staging"
    assert_includes badges2, "Development"
  end
end
