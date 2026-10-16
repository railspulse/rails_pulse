require "test_helper"

module RailsPulse
  class RollupAccumulatorTest < ActiveSupport::TestCase
    def setup
      @accumulator = RollupAccumulator.new
      @hour = Time.current.beginning_of_hour
    end

    # Structure Tests

    test "folding builds one row per subject per hour with exact sums" do
      @accumulator.fold_route(route_id: 1, occurred_at: @hour + 1.minute, duration: 100.0, status: 200)
      @accumulator.fold_route(route_id: 1, occurred_at: @hour + 2.minutes, duration: 300.0, status: 503)
      @accumulator.fold_route(route_id: 2, occurred_at: @hour + 3.minutes, duration: 50.0, status: 302)
      @accumulator.fold_query(query_id: 7, occurred_at: @hour + 1.minute, duration: 4.5)

      rows = @accumulator.drain_rows

      assert_equal 3, rows.size
      route_row = rows.find { |r| r[:rollupable_type] == "RailsPulse::Route" && r[:rollupable_id] == 1 }

      assert_equal 2, route_row[:count]
      assert_equal 1, route_row[:error_count]
      assert_equal 1, route_row[:status_2xx]
      assert_equal 1, route_row[:status_5xx]
      assert_in_delta 400.0, route_row[:sum_duration], 1e-6
      assert_in_delta 100.0**2 + 300.0**2, route_row[:sum_square_duration], 1e-6
      assert_in_delta 100.0, route_row[:min_duration], 1e-6
      assert_in_delta 300.0, route_row[:max_duration], 1e-6
      assert_equal @hour, route_row[:period_start]
      assert_equal 2, DurationHistogram.load(route_row[:histogram]).total

      query_row = rows.find { |r| r[:rollupable_type] == "RailsPulse::Query" }

      assert_equal 7, query_row[:rollupable_id]
      assert_equal 1, query_row[:count]
      assert_equal 0, query_row[:error_count]
    end

    test "requests in different hours land in different buckets" do
      @accumulator.fold_route(route_id: 1, occurred_at: @hour, duration: 10.0, status: 200)
      @accumulator.fold_route(route_id: 1, occurred_at: @hour - 1.hour, duration: 20.0, status: 200)

      rows = @accumulator.drain_rows

      assert_equal 2, rows.size
      assert_equal [ @hour - 1.hour, @hour ], rows.map { |r| r[:period_start] }.sort
    end

    test "a second drain repeats only touched buckets, with cumulative totals" do
      @accumulator.fold_route(route_id: 1, occurred_at: @hour, duration: 10.0, status: 200)
      @accumulator.fold_route(route_id: 2, occurred_at: @hour, duration: 10.0, status: 200)
      first = @accumulator.drain_rows

      @accumulator.fold_route(route_id: 1, occurred_at: @hour, duration: 30.0, status: 200)
      second = @accumulator.drain_rows

      assert_equal 2, first.size
      assert_equal 1, second.size
      assert_equal 2, second.first[:count]
      assert_in_delta 40.0, second.first[:sum_duration], 1e-6
      assert_equal first.first[:writer_id], second.first[:writer_id]
    end

    test "drain with nothing folded returns no rows" do
      assert_empty @accumulator.drain_rows
    end

    # Rotation Tests

    test "a long-ended hour rotates the writer id and clears the buckets" do
      @accumulator.fold_route(route_id: 1, occurred_at: @hour, duration: 10.0, status: 200)
      old_writer_id = @accumulator.writer_id

      rows = @accumulator.drain_rows(now: @hour + 2.hours)

      assert_equal old_writer_id, rows.first[:writer_id]
      refute_equal old_writer_id, @accumulator.writer_id
      assert_equal 0, @accumulator.bucket_count
    end

    test "a bucket never writes again under a rotated-away writer id" do
      @accumulator.fold_route(route_id: 1, occurred_at: @hour, duration: 10.0, status: 200)
      old_writer_id = @accumulator.writer_id
      @accumulator.drain_rows(now: @hour + 2.hours)

      @accumulator.fold_route(route_id: 1, occurred_at: @hour + 2.hours, duration: 20.0, status: 200)
      rows = @accumulator.drain_rows(now: @hour + 2.hours)

      assert_equal 1, rows.size
      refute_equal old_writer_id, rows.first[:writer_id]
      assert_equal 1, rows.first[:count]
    end

    test "a fresh hour within the grace period does not rotate" do
      @accumulator.fold_route(route_id: 1, occurred_at: @hour, duration: 10.0, status: 200)
      writer_id = @accumulator.writer_id

      @accumulator.drain_rows(now: @hour + 1.hour + 5.minutes)

      assert_equal writer_id, @accumulator.writer_id
      assert_equal 1, @accumulator.bucket_count
    end

    test "exceeding the bucket cap rotates" do
      max_keys = RollupAccumulator::MAX_KEYS
      (max_keys + 1).times do |i|
        @accumulator.fold_query(query_id: i, occurred_at: @hour, duration: 1.0)
      end
      writer_id = @accumulator.writer_id

      rows = @accumulator.drain_rows(now: @hour)

      assert_equal max_keys + 1, rows.size
      refute_equal writer_id, @accumulator.writer_id
      assert_equal 0, @accumulator.bucket_count
    end

    # Fork Safety Tests

    test "a forked child discards inherited buckets and takes a new writer id" do
      @accumulator.fold_route(route_id: 1, occurred_at: @hour, duration: 10.0, status: 200)
      writer_id = @accumulator.writer_id

      child_pid = Process.pid + 1
      Process.stubs(:pid).returns(child_pid)
      rows = @accumulator.drain_rows

      assert_empty rows
      refute_equal writer_id, @accumulator.writer_id
      assert_equal 0, @accumulator.bucket_count
    end

    # Flush Scheduling Tests

    test "flush is not due while nothing is dirty" do
      refute_predicate @accumulator, :flush_due?
    end

    test "flush becomes due once dirty and the interval has passed" do
      @accumulator.fold_route(route_id: 1, occurred_at: @hour, duration: 10.0, status: 200)

      refute_predicate @accumulator, :flush_due?

      later = Process.clock_gettime(Process::CLOCK_MONOTONIC) + RollupAccumulator::FLUSH_INTERVAL + 1
      Process.stubs(:clock_gettime).returns(later)

      assert_predicate @accumulator, :flush_due?
    end
  end
end
