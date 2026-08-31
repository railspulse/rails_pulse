require "test_helper"

module RailsPulse
  class FindingDetectorTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes

    def setup
      @route = rails_pulse_routes(:api_users)
      @now   = Time.utc(2026, 6, 15, 12, 0, 0)
      travel_to @now
      RailsPulse::Summary.delete_all
      RailsPulse::Finding.delete_all
    end

    def teardown
      travel_back
    end

    def summary_for(days_ago, p95:, count: 500, error_count: 0, route: nil)
      period_start = (@now - days_ago.days).beginning_of_day

      RailsPulse::Summary.create!(
        summarizable_type: "RailsPulse::Route",
        summarizable_id:   (route || @route).id,
        period_type:       "day",
        period_start:      period_start,
        period_end:        period_start.end_of_day,
        count:             count,
        avg_duration:      p95 * 0.6,
        p50_duration:      p95 * 0.5,
        p95_duration:      p95,
        p99_duration:      p95 * 1.2,
        error_count:       error_count,
        success_count:     count - error_count
      )
    end

    # A steady baseline followed by a regressed final complete day.
    def regressed_route(baseline: 200.0, current: 900.0, route: nil)
      (2..11).each { |ago| summary_for(ago, p95: baseline, route: route) }
      summary_for(1, p95: current, route: route)
    end

    def healthy_route(p95: 200.0, route: nil)
      (1..11).each { |ago| summary_for(ago, p95: p95, route: route) }
    end

    # Structure Tests

    test "records a finding for a detected regression" do
      regressed_route

      result = FindingDetector.call(as_of: @now)

      assert_equal 1, result.detected
      assert_equal 1, result.opened

      finding = Finding.sole

      assert_equal "performance_regression", finding.kind
      assert_equal "RailsPulse::Route", finding.subject_type
      assert_equal @route.id, finding.subject_id
      assert_equal "p95", finding.metric
      assert_equal "open", finding.status
      assert_in_delta 200.0, finding.baseline_value, 0.01
      assert_in_delta 900.0, finding.current_value, 0.01
    end

    test "records nothing when nothing regressed" do
      healthy_route

      result = FindingDetector.call(as_of: @now)

      assert_equal 0, result.detected
      assert_empty Finding.all
    end

    test "returns a result describing the run" do
      regressed_route

      result = FindingDetector.call(as_of: @now)

      assert_equal 1, result.detected
      assert_equal 1, result.opened
      assert_equal 0, result.reopened
      assert_equal 0, result.resolved
    end

    # Identity Tests

    test "re-detecting updates the existing finding rather than adding a row" do
      regressed_route
      # Still regressed the following day, so the second run sees it again.
      summary_for(0, p95: 900.0)

      FindingDetector.call(as_of: @now)
      FindingDetector.call(as_of: @now + 1.day)

      assert_equal 1, Finding.count
      assert_equal 2, Finding.sole.detection_count
    end

    test "first_detected_at is preserved across runs" do
      regressed_route
      summary_for(0, p95: 900.0)

      FindingDetector.call(as_of: @now)
      original = Finding.sole.first_detected_at

      FindingDetector.call(as_of: @now + 1.day)

      assert_equal original, Finding.sole.first_detected_at
      assert_equal @now + 1.day, Finding.sole.last_detected_at
    end

    test "fingerprint separates metrics on the same subject" do
      one = Finding.fingerprint_for(kind: "performance_regression", subject_type: "RailsPulse::Route", subject_id: 1, metric: "p95")
      two = Finding.fingerprint_for(kind: "error_rate_regression",  subject_type: "RailsPulse::Route", subject_id: 1, metric: "error_rate")

      assert_not_equal one, two
    end

    # Lifecycle Tests

    test "resolves a finding that stops being detected" do
      regressed_route
      FindingDetector.call(as_of: @now)

      assert_equal "open", Finding.sole.status

      # The regression clears: the last complete day is back to baseline.
      RailsPulse::Summary.delete_all
      healthy_route

      result = FindingDetector.call(as_of: @now)

      assert_equal 1, result.resolved
      assert_equal "resolved", Finding.sole.status
      assert_equal @now, Finding.sole.resolved_at
    end

    test "reopens a resolved finding rather than creating a second one" do
      regressed_route
      FindingDetector.call(as_of: @now)

      RailsPulse::Summary.delete_all
      healthy_route
      FindingDetector.call(as_of: @now)

      assert_equal "resolved", Finding.sole.status

      RailsPulse::Summary.delete_all
      regressed_route
      result = FindingDetector.call(as_of: @now)

      assert_equal 1, result.reopened
      assert_equal 1, Finding.count
      assert_equal "open", Finding.sole.status
      assert_nil Finding.sole.resolved_at
    end

    test "resolving does not touch findings the run did detect" do
      regressed_route
      FindingDetector.call(as_of: @now)
      FindingDetector.call(as_of: @now)

      assert_equal "open", Finding.sole.status
      assert_nil Finding.sole.resolved_at
    end

    # Severity Tests

    test "a regression landing above the critical threshold is critical" do
      # Default route critical threshold is 3000ms.
      regressed_route(baseline: 500.0, current: 4000.0)

      FindingDetector.call(as_of: @now)

      assert_equal "critical", Finding.sole.severity
    end

    test "a regression landing below the critical threshold is a warning" do
      regressed_route(baseline: 200.0, current: 700.0)

      FindingDetector.call(as_of: @now)

      assert_equal "warning", Finding.sole.severity
    end

    # Change Point Tests

    test "records the change point and its precision when one is found" do
      regressed_route

      FindingDetector.call(as_of: @now)
      finding = Finding.sole

      assert_predicate finding, :change_point_known?
      assert_equal "day", finding.change_point_granularity
      assert_not_predicate finding, :hourly_change_point?
    end

    # Configuration Tests

    test "skips jobs when job tracking is disabled" do
      original = RailsPulse.configuration.track_jobs
      RailsPulse.configuration.track_jobs = false

      regressed_route
      FindingDetector.call(as_of: @now)

      assert_empty Finding.where(subject_type: "RailsPulse::Job")
    ensure
      RailsPulse.configuration.track_jobs = original
    end

    # Edge Cases

    test "does nothing with no summaries at all" do
      result = FindingDetector.call(as_of: @now)

      assert_equal 0, result.detected
      assert_equal 0, result.opened
      assert_equal 0, result.resolved
    end

    test "detects independently across several subjects" do
      other = rails_pulse_routes(:api_posts)
      regressed_route
      regressed_route(route: other)

      result = FindingDetector.call(as_of: @now)

      assert_equal 2, result.detected
      assert_equal 2, Finding.count
    end
  end
end
