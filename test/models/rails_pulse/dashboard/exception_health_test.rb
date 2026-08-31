require "test_helper"

module RailsPulse
  module Dashboard
    # Before this, HealthSummary and NeedsAttention contained zero references to
    # exceptions — the two surfaces that define "where should I look" were blind
    # to errors entirely.
    class ExceptionHealthTest < ActiveSupport::TestCase
      fixtures :rails_pulse_exception_groups

      def setup
        @now = Time.current
        travel_to @now
        RailsPulse::Summary.delete_all
        RailsPulse::Finding.delete_all
        RailsPulse::Job.update_all(runs_count: 0, failures_count: 0, p95_duration: nil)
        @original_tracking = RailsPulse.configuration.track_exceptions
        RailsPulse.configuration.track_exceptions = true
      end

      def teardown
        RailsPulse.configuration.track_exceptions = @original_tracking
        travel_back
      end

      def exception_summary(group_id, count:, days_ago: 1)
        period_start = (@now - days_ago.days).beginning_of_day

        RailsPulse::Summary.create!(
          summarizable_type: "RailsPulse::ExceptionGroup",
          summarizable_id:   group_id,
          period_type:       "day",
          period_start:      period_start,
          period_end:        period_start.end_of_day,
          count:             count
        )
      end

      def open_groups
        RailsPulse::ExceptionGroup.where(status: "open")
      end

      # Health Summary Tests

      test "health summary reports exception counts" do
        health = HealthSummary.new.to_health_data

        assert_not_nil health[:exceptions]
        assert_equal open_groups.count, health[:exceptions].values.sum
      end

      test "a group above the critical threshold counts as critical" do
        exception_summary(open_groups.first.id, count: 500)

        health = HealthSummary.new.to_health_data

        assert_equal 1, health[:exceptions][:critical]
      end

      test "a group above the warning threshold counts as slow" do
        exception_summary(open_groups.first.id, count: 25)

        health = HealthSummary.new.to_health_data

        assert_equal 1, health[:exceptions][:slow]
        assert_equal 0, health[:exceptions][:critical]
      end

      test "a group firing at all is not counted as healthy" do
        # One occurrence is below the warning threshold but is still not health.
        exception_summary(open_groups.first.id, count: 1)

        health = HealthSummary.new.to_health_data

        assert_equal 1, health[:exceptions][:slow]
      end

      test "a silent open group counts as healthy" do
        health = HealthSummary.new.to_health_data

        assert_equal open_groups.count, health[:exceptions][:healthy]
      end

      test "health summary omits exceptions when tracking is disabled" do
        RailsPulse.configuration.track_exceptions = false

        assert_nil HealthSummary.new.to_health_data[:exceptions]
      end

      test "lifetime occurrence_count does not drive health" do
        # The fixture group carries occurrence_count 5 from its lifetime, but no
        # summary rows in the period: it must read as healthy today.
        group = rails_pulse_exception_groups(:record_not_found)

        assert_operator group.occurrence_count, :>, 0
        health = HealthSummary.new.to_health_data

        assert_equal 0, health[:exceptions][:critical]
      end

      # Needs Attention Tests

      test "surfaces an exception group above the warning threshold" do
        group = rails_pulse_exception_groups(:record_not_found)
        exception_summary(group.id, count: 25)

        result = NeedsAttention.new.to_attention_data
        item = (result[:critical] + result[:warning]).find { |i| i[:type] == "EXCEPTION" }

        assert_not_nil item
        assert_equal "ActiveRecord::RecordNotFound", item[:name]
        assert_includes item[:reason], "25 occurrences"
      end

      test "does not surface a group below the warning threshold" do
        exception_summary(open_groups.first.id, count: 2)

        result = NeedsAttention.new.to_attention_data
        items = (result[:critical] + result[:warning]).select { |i| i[:type] == "EXCEPTION" }

        assert_empty items
      end

      test "a group above the critical threshold is critical" do
        exception_summary(open_groups.first.id, count: 500)

        result = NeedsAttention.new.to_attention_data

        assert_equal 1, result[:critical].count { |i| i[:type] == "EXCEPTION" }
      end

      test "does not surface a resolved group" do
        resolved = rails_pulse_exception_groups(:resolved_group)
        exception_summary(resolved.id, count: 500)

        result = NeedsAttention.new.to_attention_data
        items = (result[:critical] + result[:warning]).select { |i| i[:type] == "EXCEPTION" }

        assert_empty items
      end

      test "does not surface exceptions when tracking is disabled" do
        RailsPulse.configuration.track_exceptions = false
        exception_summary(open_groups.first.id, count: 500)

        result = NeedsAttention.new.to_attention_data
        items = (result[:critical] + result[:warning]).select { |i| i[:type] == "EXCEPTION" }

        assert_empty items
      end

      test "the all-groups rollup is not reported as a group" do
        exception_summary(0, count: 500)

        result = NeedsAttention.new.to_attention_data
        items = (result[:critical] + result[:warning]).select { |i| i[:type] == "EXCEPTION" }

        assert_empty items
      end
    end
  end
end
