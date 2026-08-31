require "test_helper"

module RailsPulse
  class FindingTest < ActiveSupport::TestCase
    fixtures :rails_pulse_findings, :rails_pulse_routes

    # Structure Tests

    test "requires a fingerprint" do
      finding = build_finding(fingerprint: nil)

      assert_not finding.valid?
      assert_includes finding.errors[:fingerprint], "can't be blank"
    end

    test "fingerprints are unique" do
      existing = rails_pulse_findings(:open_route_regression)
      duplicate = build_finding(fingerprint: existing.fingerprint)

      assert_not duplicate.valid?
    end

    test "rejects an unknown status" do
      assert_not build_finding(status: "snoozed").valid?
    end

    test "rejects an unknown severity" do
      assert_not build_finding(severity: "catastrophic").valid?
    end

    test "rejects an unknown kind" do
      assert_not build_finding(kind: "vibes").valid?
    end

    # Scope Tests

    test "unresolved covers open and acknowledged but not resolved" do
      statuses = Finding.unresolved.pluck(:status).uniq.sort

      assert_equal %w[acknowledged open], statuses
    end

    test "resolved returns only resolved findings" do
      assert_equal [ "resolved" ], Finding.resolved.pluck(:status).uniq
    end

    test "recent orders by most recently detected" do
      timestamps = Finding.recent.pluck(:last_detected_at)

      assert_equal timestamps.sort.reverse, timestamps
    end

    # Fingerprint Tests

    test "fingerprint_for is stable for the same inputs" do
      args = { kind: "performance_regression", subject_type: "RailsPulse::Route", subject_id: 7, metric: "p95" }

      assert_equal Finding.fingerprint_for(**args), Finding.fingerprint_for(**args)
    end

    test "fingerprint_for separates subjects" do
      one = Finding.fingerprint_for(kind: "performance_regression", subject_type: "RailsPulse::Route", subject_id: 7, metric: "p95")
      two = Finding.fingerprint_for(kind: "performance_regression", subject_type: "RailsPulse::Route", subject_id: 8, metric: "p95")

      assert_not_equal one, two
    end

    # Presentation Tests

    test "percent_change derives from the ratio" do
      finding = rails_pulse_findings(:open_query_regression)

      assert_in_delta 200.0, finding.percent_change, 0.01
    end

    test "unit is milliseconds for duration metrics" do
      assert_equal "ms", rails_pulse_findings(:open_route_regression).unit
    end

    test "unit is percent for error rate" do
      assert_equal "%", rails_pulse_findings(:acknowledged_error_rate_regression).unit
    end

    test "change point precision is reported" do
      hourly = rails_pulse_findings(:open_route_regression)
      daily  = rails_pulse_findings(:open_query_regression)

      assert_predicate hourly, :hourly_change_point?
      assert_not_predicate daily, :hourly_change_point?
      assert_predicate daily, :change_point_known?
    end

    test "a finding with no change point says so" do
      finding = rails_pulse_findings(:acknowledged_error_rate_regression)

      assert_not_predicate finding, :change_point_known?
    end

    test "subject_label falls back when the subject has been cleaned up" do
      finding = build_finding(subject_id: 999_999)

      assert_equal "Route #999999", finding.subject_label
    end

    test "the overall request rollup has no record and is labelled" do
      finding = build_finding(subject_type: "RailsPulse::Request", subject_id: 0)

      assert_predicate finding, :overall_requests?
      assert_nil finding.subject
      assert_equal "All requests", finding.subject_label
    end

    test "to_s renders both sides of the change" do
      finding = rails_pulse_findings(:open_route_regression)

      assert_includes finding.to_s, "220ms"
      assert_includes finding.to_s, "1420ms"
    end

    # Ransack Tests

    test "exposes ransackable attributes" do
      assert_includes Finding.ransackable_attributes, "severity"
      assert_includes Finding.ransackable_attributes, "status"
      assert_includes Finding.ransackable_attributes, "last_detected_at"
    end

    private

    def build_finding(**overrides)
      Finding.new({
        fingerprint:       SecureRandom.hex(32),
        kind:              "performance_regression",
        subject_type:      "RailsPulse::Route",
        subject_id:        1,
        metric:            "p95",
        severity:          "warning",
        status:            "open",
        first_detected_at: Time.current,
        last_detected_at:  Time.current
      }.merge(overrides))
    end
  end
end
