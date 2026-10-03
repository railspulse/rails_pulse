require "test_helper"

module RailsPulse
  class DeploymentComparisonTest < ActiveSupport::TestCase
    # A deploy at 14:28 compares the hour 13:00-14:00 with 15:00-16:00; the
    # deploy hour itself mixes both versions and is skipped.
    NOW         = Time.zone.parse("2026-01-15 17:00:00").freeze
    DEPLOY_TIME = Time.zone.parse("2026-01-15 14:28:00").freeze
    BEFORE_HOUR = Time.zone.parse("2026-01-15 13:00:00").freeze
    AFTER_HOUR  = Time.zone.parse("2026-01-15 15:00:00").freeze

    def setup
      travel_to NOW
      RailsPulse::Summary.delete_all
      RailsPulse::Deployment.delete_all
      @deployment = RailsPulse::Deployment.create!(revision: "abc123", started_at: DEPLOY_TIME)
    end

    def teardown
      travel_back
    end

    # Structure Tests

    test "compares the hour before the deploy hour with the hour after it" do
      seed(before: { avg: 200.0 }, after: { avg: 200.0 })
      result = compare

      assert_equal BEFORE_HOUR, result[:before][:from]
      assert_equal BEFORE_HOUR + 1.hour, result[:before][:to]
      assert_equal AFTER_HOUR, result[:after][:from]
      assert_equal 20, result[:after][:requests]
      assert_equal %i[avg_response_time p95_response_time error_rate], result[:metrics].map { |m| m[:metric] }
    end

    test "ignores traffic in the deploy hour" do
      seed(before: { avg: 200.0 }, after: { avg: 200.0 })
      overall_row(Time.zone.parse("2026-01-15 14:00:00"), avg: 5_000.0)

      assert_equal "clean", compare[:outcome]
    end

    test "for compares a page of deployments keyed by id" do
      other = RailsPulse::Deployment.create!(revision: "def456", started_at: DEPLOY_TIME - 1.day)
      seed(before: { avg: 200.0 }, after: { avg: 400.0 })

      results = DeploymentComparison.for([ @deployment, other ])

      assert_equal "degraded", results[@deployment.id][:outcome]
      assert_equal "pending", results[other.id][:outcome]
    end

    test "for returns an empty hash for no deployments" do
      assert_empty(DeploymentComparison.for([]))
    end

    # Calculation Tests

    test "clean when every metric is within its multiplier" do
      # avg 200 -> 290 is 1.45x, under 1.5x
      seed(before: { avg: 200.0 }, after: { avg: 290.0 })
      result = compare

      assert_equal "clean", result[:outcome]
      assert_in_delta 1.45, metric(result, :avg_response_time)[:ratio]
      assert_nil result[:note]
    end

    test "average response time more than 1.5x worse is degraded" do
      seed(before: { avg: 200.0 }, after: { avg: 301.0 })
      result = compare
      avg = metric(result, :avg_response_time)

      assert_equal "degraded", result[:outcome]
      assert_equal "degraded", avg[:outcome]
      assert_in_delta 200.0, avg[:before]
      assert_in_delta 301.0, avg[:after]
      assert_in_delta 1.5, avg[:multiplier]
      assert_equal "ms", avg[:unit]
    end

    test "exactly 1.5x is not degraded" do
      seed(before: { avg: 200.0 }, after: { avg: 300.0 })

      assert_equal "clean", compare[:outcome]
    end

    test "p95 response time more than 1.5x worse is degraded" do
      seed(before: { avg: 100.0, p95: 300.0 }, after: { avg: 100.0, p95: 600.0 })
      result = compare

      assert_equal "degraded", metric(result, :p95_response_time)[:outcome]
      assert_equal "clean", metric(result, :avg_response_time)[:outcome]
    end

    test "error rate more than 1.25x worse is degraded" do
      # 2/20 = 10% before, 3/20 = 15% after: 1.5x
      seed(before: { avg: 100.0, errors: 2 }, after: { avg: 100.0, errors: 3 })
      error_rate = metric(compare, :error_rate)

      assert_equal "degraded", error_rate[:outcome]
      assert_in_delta 10.0, error_rate[:before]
      assert_in_delta 15.0, error_rate[:after]
      assert_equal "%", error_rate[:unit]
    end

    test "error rate within 1.25x is clean" do
      # 4/20 = 20% before, 5/20 = 25% after: exactly 1.25x
      seed(before: { avg: 100.0, errors: 4 }, after: { avg: 100.0, errors: 5 })

      assert_equal "clean", metric(compare, :error_rate)[:outcome]
    end

    # Edge Cases

    test "errors after a deploy with none before is degraded without a ratio" do
      seed(before: { avg: 100.0, errors: 0 }, after: { avg: 100.0, errors: 1 })
      error_rate = metric(compare, :error_rate)

      assert_equal "degraded", error_rate[:outcome]
      assert_nil error_rate[:ratio]
    end

    test "no errors on either side is clean" do
      seed(before: { avg: 100.0 }, after: { avg: 100.0 })
      error_rate = metric(compare, :error_rate)

      assert_equal "clean", error_rate[:outcome]
      assert_nil error_rate[:ratio]
    end

    test "fewer than 10 requests before the deploy is insufficient data" do
      seed(before: { avg: 100.0, count: 9 }, after: { avg: 400.0 })
      result = compare

      assert_equal "insufficient_data", result[:outcome]
      assert(result[:metrics].all? { |m| m[:outcome] == "insufficient_data" && m[:ratio].nil? })
      assert_includes result[:note], "Fewer than 10 requests"
    end

    test "fewer than 10 requests after the deploy is insufficient data" do
      seed(before: { avg: 100.0 }, after: { avg: 400.0, count: 9 })

      assert_equal "insufficient_data", compare[:outcome]
    end

    test "exactly 10 requests in each window is enough" do
      seed(before: { avg: 100.0, count: 10 }, after: { avg: 400.0, count: 10 })

      assert_equal "degraded", compare[:outcome]
    end

    test "no summary for the hour before is insufficient data" do
      seed(after: { avg: 100.0 })
      result = compare

      assert_equal "insufficient_data", result[:outcome]
      assert_equal 0, result[:before][:requests]
    end

    test "an hour after that has not ended yet is pending" do
      travel_to Time.zone.parse("2026-01-15 15:30:00")
      seed(before: { avg: 100.0 })
      result = compare

      assert_equal "pending", result[:outcome]
      assert_includes result[:note], "available once SummaryJob has summarized it"
    end

    test "an hour after that has ended but is not summarized is pending" do
      seed(before: { avg: 100.0 })
      result = compare

      assert_equal "pending", result[:outcome]
      assert_includes result[:note], "SummaryJob is scheduled"
    end

    test "a deployment older than hourly summary retention cannot be compared" do
      old = RailsPulse::Deployment.create!(revision: "old", started_at: NOW - 10.days)
      result = DeploymentComparison.new(old).call

      assert_equal "insufficient_data", result[:outcome]
      assert_includes result[:note], "pruned"
    end

    test "an in-progress deployment is compared from its start" do
      running = RailsPulse::Deployment.create!(revision: "running", started_at: NOW - 5.minutes)

      assert_equal "pending", DeploymentComparison.new(running).call[:outcome]
    end

    test "route summaries are not read" do
      seed(before: { avg: 100.0 }, after: { avg: 100.0 })
      RailsPulse::Summary.create!(
        summarizable_type: "RailsPulse::Route", summarizable_id: 1, period_type: "hour",
        period_start: AFTER_HOUR, period_end: AFTER_HOUR.end_of_hour,
        count: 500, avg_duration: 9_000.0, p95_duration: 9_000.0, error_count: 0, success_count: 500
      )

      assert_equal "clean", compare[:outcome]
    end

    private

    def compare
      DeploymentComparison.new(@deployment).call
    end

    def metric(result, name)
      result[:metrics].find { |m| m[:metric] == name }
    end

    def seed(before: nil, after: nil)
      overall_row(BEFORE_HOUR, **before) if before
      overall_row(AFTER_HOUR, **after) if after
    end

    def overall_row(period_start, avg:, p95: nil, errors: 0, count: 20)
      RailsPulse::Summary.create!(
        summarizable_type: "RailsPulse::Request",
        summarizable_id:   0,
        period_type:       "hour",
        period_start:      period_start,
        period_end:        period_start.end_of_hour,
        count:             count,
        avg_duration:      avg,
        p95_duration:      p95 || avg,
        error_count:       errors,
        success_count:     count - errors
      )
    end
  end
end
