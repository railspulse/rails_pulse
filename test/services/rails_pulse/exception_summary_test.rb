require "test_helper"

module RailsPulse
  # Exception frequency has to survive retention. ExceptionGroup#occurrence_count
  # is a lifetime counter and occurrence rows are pruned, so without summaries
  # there is no way to ask how often something happened last week.
  class ExceptionSummaryTest < ActiveSupport::TestCase
    fixtures :rails_pulse_exception_groups

    def setup
      @group = rails_pulse_exception_groups(:record_not_found)
      @hour  = Time.utc(2026, 6, 15, 10, 0, 0)
      travel_to @hour + 30.minutes
      RailsPulse::Summary.delete_all
      RailsPulse::ExceptionOccurrence.delete_all
      @original_tracking = RailsPulse.configuration.track_exceptions
      RailsPulse.configuration.track_exceptions = true
    end

    def teardown
      RailsPulse.configuration.track_exceptions = @original_tracking
      travel_back
    end

    def occurrence_at(time, group: nil)
      RailsPulse::ExceptionOccurrence.create!(
        exception_group: group || @group,
        exception_class: (group || @group).exception_class,
        message:         "boom",
        occurred_at:     time
      )
    end

    def summarize
      SummaryService.new("hour", @hour).perform
    end

    def group_summary(group_id)
      RailsPulse::Summary.find_by(
        summarizable_type: "RailsPulse::ExceptionGroup",
        summarizable_id:   group_id,
        period_type:       "hour",
        period_start:      @hour
      )
    end

    # Structure Tests

    test "records a per-group count for the period" do
      3.times { occurrence_at(@hour + 5.minutes) }

      summarize

      assert_equal 3, group_summary(@group.id).count
    end

    test "records an all-groups rollup" do
      other = rails_pulse_exception_groups(:zero_division)
      2.times { occurrence_at(@hour + 5.minutes) }
      3.times { occurrence_at(@hour + 6.minutes, group: other) }

      summarize

      assert_equal 5, group_summary(0).count
    end

    test "leaves duration columns null because exceptions have no duration" do
      occurrence_at(@hour + 5.minutes)

      summarize
      summary = group_summary(@group.id)

      assert_nil summary.p95_duration
      assert_nil summary.avg_duration
    end

    test "sets the period boundaries" do
      occurrence_at(@hour + 5.minutes)

      summarize
      summary = group_summary(@group.id)

      assert_equal @hour, summary.period_start
      assert_equal @hour.end_of_hour.change(usec: 0), summary.period_end.change(usec: 0)
    end

    # Scoping Tests

    test "counts only occurrences inside the period" do
      occurrence_at(@hour - 10.minutes)
      occurrence_at(@hour + 5.minutes)
      occurrence_at(@hour + 2.hours)

      summarize

      assert_equal 1, group_summary(@group.id).count
    end

    test "re-running the summary replaces rather than doubles the count" do
      2.times { occurrence_at(@hour + 5.minutes) }

      summarize
      summarize

      assert_equal 2, group_summary(@group.id).count
      assert_equal 1, RailsPulse::Summary.for_exceptions.where(summarizable_id: @group.id).count
    end

    # Configuration Tests

    test "writes nothing when exception tracking is disabled" do
      RailsPulse.configuration.track_exceptions = false
      occurrence_at(@hour + 5.minutes)

      summarize

      assert_empty RailsPulse::Summary.for_exceptions
    end

    # Edge Cases

    test "writes nothing when no exceptions occurred" do
      summarize

      assert_empty RailsPulse::Summary.for_exceptions
    end

    test "route and query summaries still run when exceptions are present" do
      occurrence_at(@hour + 5.minutes)

      # The exception aggregation must not raise in a way that rolls back the
      # rest of the transaction.
      assert_nothing_raised { summarize }
    end

    # Scope Tests

    test "for_exceptions returns only exception summaries" do
      occurrence_at(@hour + 5.minutes)
      summarize

      types = RailsPulse::Summary.for_exceptions.pluck(:summarizable_type).uniq

      assert_equal [ "RailsPulse::ExceptionGroup" ], types
    end

    test "overall_exceptions returns only the rollup row" do
      occurrence_at(@hour + 5.minutes)
      summarize

      assert_equal [ 0 ], RailsPulse::Summary.overall_exceptions.pluck(:summarizable_id).uniq
    end

    test "exception summaries pass through the tag filter" do
      occurrence_at(@hour + 5.minutes)
      summarize

      # Exception groups have no tags column, so disabling every tag must not
      # hide them the way it would hide an untagged route.
      filtered = RailsPulse::Summary.with_tag_filters([ "critical" ], false).for_exceptions

      assert_operator filtered.count, :>, 0
    end
  end
end
