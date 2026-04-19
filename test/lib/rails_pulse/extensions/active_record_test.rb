require "test_helper"

module RailsPulse
  module Extensions
    class ActiveRecordTest < ActiveSupport::TestCase
      fixtures :rails_pulse_summaries

      def setup
        super
        RailsPulse::Summary.delete_all

        @now = Time.current
        travel_to @now
      end

      def teardown
        travel_back
        super
      end

      # group_by_date Tests — Structure

      # Helper to get a relation (group_by_date/hour work on relations, not class directly)
      def day_summaries
        RailsPulse::Summary.where(period_type: "day")
      end

      def hour_summaries
        RailsPulse::Summary.where(period_type: "hour")
      end

      test "group_by_date returns a hash" do
        create_summary(days_ago: 1)

        result = day_summaries.group_by_date(:period_start).count

        assert_kind_of Hash, result
      end

      test "group_by_date returns Date keys" do
        create_summary(days_ago: 1)

        result = day_summaries.group_by_date(:period_start).count

        result.each_key { |k| assert_kind_of Date, k }
      end

      # group_by_date Calculation Tests

      test "group_by_date count groups correctly by date" do
        create_summary(days_ago: 1)
        create_summary(days_ago: 1)
        create_summary(days_ago: 2)

        result = day_summaries.group_by_date(:period_start).count

        assert_equal 2, result.size
        # The date 1 day ago should have count 2
        one_day_ago = 1.day.ago.to_date

        assert_equal 2, result[one_day_ago]
      end

      test "group_by_date sum returns correct totals" do
        create_summary(days_ago: 1, count: 10)
        create_summary(days_ago: 1, count: 20)

        result = day_summaries.group_by_date(:period_start).sum(:count)

        one_day_ago = 1.day.ago.to_date

        assert_equal 30, result[one_day_ago]
      end

      test "group_by_date average returns correct averages" do
        create_summary(days_ago: 1, avg_duration: 100.0)
        create_summary(days_ago: 1, avg_duration: 200.0)

        result = day_summaries.group_by_date(:period_start).average(:avg_duration)

        one_day_ago = 1.day.ago.to_date

        assert_in_delta 150.0, result[one_day_ago], 0.1
      end

      test "group_by_date maximum returns correct max" do
        create_summary(days_ago: 1, avg_duration: 100.0)
        create_summary(days_ago: 1, avg_duration: 300.0)

        result = day_summaries.group_by_date(:period_start).maximum(:avg_duration)

        one_day_ago = 1.day.ago.to_date

        assert_in_delta 300.0, result[one_day_ago], 0.1
      end

      test "group_by_date minimum returns correct min" do
        create_summary(days_ago: 1, avg_duration: 100.0)
        create_summary(days_ago: 1, avg_duration: 300.0)

        result = day_summaries.group_by_date(:period_start).minimum(:avg_duration)

        one_day_ago = 1.day.ago.to_date

        assert_in_delta 100.0, result[one_day_ago], 0.1
      end

      # group_by_hour Tests — Structure

      test "group_by_hour returns a hash" do
        create_summary(hours_ago: 1)

        result = hour_summaries.group_by_hour(:period_start).count

        assert_kind_of Hash, result
      end

      test "group_by_hour returns Time keys" do
        create_summary(hours_ago: 1)

        result = hour_summaries.group_by_hour(:period_start).count

        result.each_key { |k| assert_kind_of Time, k }
      end

      # group_by_hour Calculation Tests

      test "group_by_hour groups by hour" do
        create_summary(hours_ago: 1)
        create_summary(hours_ago: 1)
        create_summary(hours_ago: 2)

        result = hour_summaries.group_by_hour(:period_start).count

        assert_equal 2, result.size
      end

      test "group_by_hour sum returns correct totals" do
        create_summary(hours_ago: 1, count: 5)
        create_summary(hours_ago: 1, count: 15)

        result = hour_summaries.group_by_hour(:period_start).sum(:count)

        assert_equal 20, result.values.sum
      end

      # Edge Cases

      test "group_by_date returns empty hash for no records" do
        result = day_summaries.group_by_date(:period_start).count

        assert_empty(result)
      end

      test "group_by_hour returns empty hash for no records" do
        result = hour_summaries.group_by_hour(:period_start).count

        assert_empty(result)
      end

      test "group_by_date handles single record" do
        create_summary(days_ago: 3)

        result = day_summaries.group_by_date(:period_start).count

        assert_equal 1, result.size
        assert_equal 1, result.values.first
      end

      private

      def next_summarizable_id
        @summarizable_id_seq = (@summarizable_id_seq || 0) + 1
      end

      def create_summary(days_ago: nil, hours_ago: nil, count: 1, avg_duration: 0.0)
        if days_ago
          period_start = days_ago.days.ago.beginning_of_day
          period_type = "day"
        else
          period_start = hours_ago.hours.ago.beginning_of_hour
          period_type = "hour"
        end

        # Use unique summarizable_id per record to satisfy the unique index on
        # (summarizable_type, summarizable_id, period_type, period_start)
        RailsPulse::Summary.create!(
          summarizable_type: "RailsPulse::Route",
          summarizable_id: next_summarizable_id,
          period_start: period_start,
          period_end: period_start + 1.hour,
          period_type: period_type,
          count: count,
          avg_duration: avg_duration
        )
      end
    end
  end
end
