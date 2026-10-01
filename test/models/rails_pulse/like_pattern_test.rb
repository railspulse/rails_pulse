require "test_helper"

module RailsPulse
  class LikePatternTest < ActiveSupport::TestCase
    # Structure Tests

    test "CLAUSE names the escape character" do
      assert_equal "ESCAPE '#{RailsPulse::LikePattern::ESCAPE_CHARACTER}'", RailsPulse::LikePattern::CLAUSE
    end

    # Escaping Tests

    test "escape neutralises an underscore" do
      assert_equal "work!_orders", RailsPulse::LikePattern.escape("work_orders")
    end

    test "escape neutralises a percent sign" do
      assert_equal "100!% done", RailsPulse::LikePattern.escape("100% done")
    end

    test "escape neutralises the escape character itself" do
      assert_equal "a!!b", RailsPulse::LikePattern.escape("a!b")
    end

    test "escape leaves a backslash alone" do
      assert_equal "a\\b", RailsPulse::LikePattern.escape("a\\b")
    end

    test "escape coerces non-string input" do
      assert_equal "42", RailsPulse::LikePattern.escape(42)
    end

    # Pattern Tests

    test "containing wraps the escaped value in wildcards" do
      assert_equal "%work!_orders%", RailsPulse::LikePattern.containing("work_orders")
    end

    # Edge Cases

    test "escape returns an empty string for nil" do
      assert_equal "", RailsPulse::LikePattern.escape(nil)
    end

    test "containing matches everything for an empty value" do
      assert_equal "%%", RailsPulse::LikePattern.containing("")
    end
  end
end
