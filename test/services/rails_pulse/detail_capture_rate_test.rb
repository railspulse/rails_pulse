require "test_helper"

module RailsPulse
  class DetailCaptureRateTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes, :rails_pulse_queries

    def setup
      Summary.delete_all
      Rollup.delete_all
      travel_to Time.zone.parse("2026-10-14 12:30:00")
      @users = rails_pulse_routes(:api_users)
      @posts = rails_pulse_routes(:api_posts)
      @query = rails_pulse_queries(:simple_query)
    end

    def teardown
      travel_back
    end

    # Calculation Tests

    test "the kept share is each hour's total less what was folded" do
      overall(2.hours.ago, 100)
      overall(1.hour.ago, 300)
      folded(@users, 2.hours.ago, 90)
      folded(@users, 1.hour.ago, 200)
      folded(@posts, 1.hour.ago, 90)

      rate = DetailCaptureRate.for

      assert_equal 400, rate.total
      assert_equal 20, rate.kept
      assert_in_delta 0.05, rate.share
    end

    test "folded counts from every writer are summed" do
      overall(1.hour.ago, 100)
      folded(@users, 1.hour.ago, 40, writer: "web-1")
      folded(@users, 1.hour.ago, 50, writer: "web-2")

      assert_equal 10, DetailCaptureRate.for.kept
    end

    test "a route's share counts only its own requests" do
      route(@users, 1.hour.ago, 50)
      folded(@users, 1.hour.ago, 40)
      folded(@posts, 1.hour.ago, 500)

      rate = DetailCaptureRate.for(@users)

      assert_equal 50, rate.total
      assert_equal 10, rate.kept
    end

    test "a route with nothing folded is fully kept once any route has folded" do
      route(@users, 1.hour.ago, 30)
      folded(@posts, 1.hour.ago, 500)

      assert_in_delta 1.0, DetailCaptureRate.for(@users).share
    end

    test "a query's share counts its executions" do
      Summary.create!(summarizable: @query, **hour(1.hour.ago), count: 80)
      folded(@query, 1.hour.ago, 60)

      rate = DetailCaptureRate.for(@query)

      assert_equal 80, rate.total
      assert_equal 20, rate.kept
    end

    test "the routes keeping the most come first" do
      route(@users, 1.hour.ago, 100)
      route(@posts, 1.hour.ago, 100)
      folded(@users, 1.hour.ago, 90)
      folded(@posts, 1.hour.ago, 40)

      top = DetailCaptureRate.top_kept_routes

      assert_equal [ [ @posts, 60, 100 ], [ @users, 10, 100 ] ], top
    end

    test "the routes keeping the most read as one label" do
      route(@users, 1.hour.ago, 1500)
      folded(@users, 1.hour.ago, 100)

      assert_equal "/api/users (1,400 of 1,500)", DetailCaptureRate.top_kept_routes_label
    end

    test "the retune advice names each setting with its value" do
      config = RailsPulse::Configuration.new
      config.store_full_details = { above_threshold: :slow }

      assert_equal "raise request_thresholds[:slow] (700ms now) or query_thresholds[:slow] (100ms now), " \
                   "set store_full_details[:above_threshold] to a higher threshold, or lower store_full_details[:sample_rate_below] (1% now)",
                   DetailCaptureRate.retune_advice(config.detail_capture_settings)

      config.store_full_details = { above_threshold: :critical, sample_rate_below: 0 }

      assert_equal "raise request_thresholds[:critical] (4000ms now) or query_thresholds[:critical] (1000ms now), " \
                   "set store_full_details[:above_threshold] to a higher threshold",
                   DetailCaptureRate.retune_advice(config.detail_capture_settings)
    end

    # Edge Cases

    test "share labels round to one place and floor tiny shares" do
      overall(1.hour.ago, 100_000)
      folded(@users, 1.hour.ago, 82_300)

      assert_equal "17.7%", DetailCaptureRate.for.share_label

      folded(@users, 1.hour.ago, 99_990)

      assert_equal "under 0.1%", DetailCaptureRate.for.share_label

      folded(@users, 1.hour.ago, 75_000)

      assert_equal "25%", DetailCaptureRate.for.share_label
    end

    test "no routes kept anything means no label" do
      route(@users, 1.hour.ago, 10)
      folded(@users, 1.hour.ago, 10)

      assert_nil DetailCaptureRate.top_kept_routes_label
    end

    test "hours from before anything was folded do not count" do
      overall(5.hours.ago, 1000)
      overall(1.hour.ago, 100)
      folded(@users, 1.hour.ago, 95)

      assert_equal 100, DetailCaptureRate.for.total
    end

    test "the current hour's rollups wait for its summary" do
      overall(1.hour.ago, 100)
      folded(@users, 1.hour.ago, 90)
      folded(@users, Time.current, 400)

      assert_equal 10, DetailCaptureRate.for.kept
    end

    test "hours older than a day do not count" do
      overall(30.hours.ago, 100)
      folded(@users, 30.hours.ago, 10)
      overall(1.hour.ago, 100)
      folded(@users, 1.hour.ago, 90)

      assert_equal 10, DetailCaptureRate.for.kept
    end

    test "the rate is unknown with nothing folded in the last day" do
      overall(1.hour.ago, 100)

      assert_nil DetailCaptureRate.for
    end

    test "the rate is unknown before any folded hour is summarized" do
      folded(@users, Time.current, 50)

      assert_nil DetailCaptureRate.for
    end

    test "the rate is unknown for hours with no traffic" do
      overall(1.hour.ago, 0)
      folded(@users, 1.hour.ago, 0)

      assert_nil DetailCaptureRate.for
    end

    test "kept never goes negative" do
      overall(1.hour.ago, 10)
      folded(@users, 1.hour.ago, 12)

      assert_equal 0, DetailCaptureRate.for.kept
    end

    test "a quarter kept is not high, just over is" do
      overall(1.hour.ago, 100)
      folded(@users, 1.hour.ago, 75)

      assert_not DetailCaptureRate.for.high?

      folded(@users, 1.hour.ago, 74)

      assert_predicate DetailCaptureRate.for, :high?
    end

    private

    def hour(time)
      start = time.beginning_of_hour
      { period_type: "hour", period_start: start, period_end: start.end_of_hour }
    end

    def overall(time, count)
      Summary.create!(summarizable_type: "RailsPulse::Request", summarizable_id: 0, **hour(time), count: count)
    end

    def route(route, time, count)
      Summary.create!(summarizable: route, **hour(time), count: count)
    end

    # Replaces the writer's row, as a flush does
    def folded(rollupable, time, count, writer: "web-1")
      Rollup.where(rollupable: rollupable, period_start: time.beginning_of_hour, writer_id: writer).delete_all
      Rollup.create!(rollupable: rollupable, period_start: time.beginning_of_hour, writer_id: writer, count: count)
    end
  end
end
