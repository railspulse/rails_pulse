require "test_helper"

module RailsPulse
  class RollupTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes

    def setup
      @route = rails_pulse_routes(:api_users)
      @hour = 2.hours.ago.beginning_of_hour
    end

    def base_row(overrides = {})
      {
        rollupable_type: "RailsPulse::Route",
        rollupable_id: @route.id,
        period_start: @hour,
        writer_id: "host:1:abc",
        count: 5,
        error_count: 1,
        status_2xx: 4, status_3xx: 0, status_4xx: 0, status_5xx: 1,
        sum_duration: 500.0,
        sum_square_duration: 70_000.0,
        min_duration: 20.0,
        max_duration: 300.0,
        histogram: "{}",
        created_at: Time.current,
        updated_at: Time.current
      }.merge(overrides)
    end

    # Upsert Tests

    test "upsert_rows inserts a new row" do
      assert_difference "RailsPulse::Rollup.count", 1 do
        Rollup.upsert_rows([ base_row ])
      end
    end

    test "upsert_rows replaces the row for the same subject, hour and writer" do
      Rollup.upsert_rows([ base_row ])

      assert_no_difference "RailsPulse::Rollup.count" do
        Rollup.upsert_rows([ base_row(count: 9, sum_duration: 900.0) ])
      end

      row = Rollup.find_by!(writer_id: "host:1:abc")

      assert_equal 9, row.count
      assert_in_delta 900.0, row.sum_duration.to_f, 1e-6
    end

    test "upsert_rows keeps rows from different writers apart" do
      Rollup.upsert_rows([ base_row ])

      assert_difference "RailsPulse::Rollup.count", 1 do
        Rollup.upsert_rows([ base_row(writer_id: "host:2:def", count: 3) ])
      end

      assert_equal [ 3, 5 ], Rollup.where(period_start: @hour).order(:count).pluck(:count)
    end

    test "upsert_rows with no rows is a no-op" do
      assert_no_difference "RailsPulse::Rollup.count" do
        Rollup.upsert_rows([])
      end
    end

    # Edge Cases

    test "histogram_counts loads the serialized histogram" do
      histogram = DurationHistogram.new
      histogram.record(42.0)
      Rollup.upsert_rows([ base_row(histogram: histogram.dump) ])

      counts = Rollup.find_by!(writer_id: "host:1:abc").histogram_counts

      assert_equal histogram.counts, counts
    end
  end
end
