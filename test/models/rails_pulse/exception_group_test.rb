require "test_helper"

module RailsPulse
  class ExceptionGroupTest < ActiveSupport::TestCase
    fixtures :rails_pulse_exception_groups, :rails_pulse_exception_occurrences

    def setup
      ENV["TEST_TYPE"] = "functional"
      super
    end

    # Validations

    test "validates presence of fingerprint" do
      group = ExceptionGroup.new(exception_class: "RuntimeError", first_seen_at: Time.current, last_seen_at: Time.current)

      refute_predicate group, :valid?
      assert_includes group.errors[:fingerprint], "can't be blank"
    end

    test "validates presence of exception_class" do
      group = ExceptionGroup.new(fingerprint: "unique123", first_seen_at: Time.current, last_seen_at: Time.current)

      refute_predicate group, :valid?
      assert_includes group.errors[:exception_class], "can't be blank"
    end

    test "validates presence of first_seen_at and last_seen_at" do
      group = ExceptionGroup.new(fingerprint: "unique456", exception_class: "RuntimeError")

      refute_predicate group, :valid?
      assert_includes group.errors[:first_seen_at], "can't be blank"
      assert_includes group.errors[:last_seen_at], "can't be blank"
    end

    test "valid group saves successfully" do
      assert_difference -> { ExceptionGroup.count }, 1 do
        ExceptionGroup.create!(
          fingerprint: "new_fp_abc123",
          exception_class: "RuntimeError",
          first_seen_at: Time.current,
          last_seen_at: Time.current
        )
      end
    end

    # Associations

    test "has many occurrences" do
      group = rails_pulse_exception_groups(:record_not_found)

      assert_operator group.occurrences.count, :>=, 1
    end

    test "destroying group destroys occurrences" do
      group = rails_pulse_exception_groups(:zero_division)
      count_before = ExceptionOccurrence.where(exception_group: group).count

      assert_difference -> { ExceptionOccurrence.count }, -count_before do
        group.destroy
      end
    end

    # Scopes

    test "recent orders by last_seen_at desc" do
      results = ExceptionGroup.recent

      results.each_cons(2) do |a, b|
        assert_operator a.last_seen_at, :>=, b.last_seen_at
      end
    end

    test "by_class filters by exception class" do
      results = ExceptionGroup.by_class("ActiveRecord::RecordNotFound")

      assert_includes results.map(&:exception_class), "ActiveRecord::RecordNotFound"
      refute_includes results.map(&:exception_class), "ZeroDivisionError"
    end

    # Ransack

    test "ransackable_attributes returns expected fields" do
      attrs = ExceptionGroup.ransackable_attributes

      assert_includes attrs, "exception_class"
      assert_includes attrs, "fingerprint"
      assert_includes attrs, "occurrence_count"
      assert_includes attrs, "first_seen_at"
      assert_includes attrs, "last_seen_at"
      assert_includes attrs, "location"
    end

    test "to_breadcrumb returns the exception class" do
      group = rails_pulse_exception_groups(:record_not_found)

      assert_equal "ActiveRecord::RecordNotFound", group.to_breadcrumb
    end
  end
end
