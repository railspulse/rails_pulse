require "test_helper"

module RailsPulse
  class DeploymentCorrelatorTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes

    def setup
      @now = Time.utc(2026, 6, 15, 12, 0, 0)
      travel_to @now
      RailsPulse::Deployment.delete_all
      RailsPulse::Finding.delete_all
    end

    def teardown
      travel_back
    end

    def deployment_at(time, revision: SecureRandom.hex(6))
      RailsPulse::Deployment.create!(revision: revision, started_at: time)
    end

    def finding_with_change_point(changed_at, granularity: "hour")
      RailsPulse::Finding.create!(
        fingerprint:       SecureRandom.hex(32),
        kind:              "performance_regression",
        subject_type:      "RailsPulse::Route",
        subject_id:        rails_pulse_routes(:api_users).id,
        metric:            "p95",
        severity:          "warning",
        status:            "open",
        baseline_value:    200.0,
        current_value:     900.0,
        delta:             700.0,
        ratio:             4.5,
        changed_at:        changed_at,
        change_point_granularity: granularity,
        first_detected_at: @now,
        last_detected_at:  @now,
        detection_count:   1
      )
    end

    # Structure Tests

    test "returns the deployment shortly before an hourly change point" do
      deployment = deployment_at(@now - 3.hours)
      finding    = finding_with_change_point(@now - 2.hours)

      assert_equal deployment, DeploymentCorrelator.for(finding)
    end

    test "returns nil when no deployment is close enough" do
      deployment_at(@now - 3.days)
      finding = finding_with_change_point(@now - 2.hours)

      assert_nil DeploymentCorrelator.for(finding)
    end

    test "returns nil when the finding has no change point" do
      deployment_at(@now - 1.hour)
      finding = finding_with_change_point(nil, granularity: nil)

      assert_nil DeploymentCorrelator.for(finding)
    end

    # Selection Tests

    test "picks the most recent deployment when several are in range" do
      deployment_at(@now - 5.hours)
      nearest = deployment_at(@now - 3.hours)
      finding = finding_with_change_point(@now - 2.hours)

      assert_equal nearest, DeploymentCorrelator.for(finding)
    end

    test "does not pick a deployment after an hourly change point" do
      # An hourly change point is accurate, so a deploy that happened afterwards
      # cannot have caused it.
      deployment_at(@now - 1.hour)
      finding = finding_with_change_point(@now - 2.hours)

      assert_nil DeploymentCorrelator.for(finding)
    end

    test "a daily change point admits deployments later in that day" do
      # The change point only identifies the day, so a deploy that morning is a
      # candidate even though its timestamp is after the midnight boundary.
      day        = (@now - 2.days).beginning_of_day
      deployment = deployment_at(day + 9.hours)
      finding    = finding_with_change_point(day, granularity: "day")

      assert_equal deployment, DeploymentCorrelator.for(finding)
    end

    # Batch Tests

    test "for_all correlates a batch" do
      deployment = deployment_at(@now - 3.hours)
      finding    = finding_with_change_point(@now - 2.hours)

      correlated = DeploymentCorrelator.for_all([ finding ])

      assert_equal deployment, correlated[finding.id]
    end

    test "for_all omits findings with no match" do
      finding = finding_with_change_point(@now - 2.hours)

      assert_empty DeploymentCorrelator.for_all([ finding ])
    end

    test "for_all skips findings without a change point" do
      deployment_at(@now - 1.hour)
      finding = finding_with_change_point(nil, granularity: nil)

      assert_empty DeploymentCorrelator.for_all([ finding ])
    end

    test "for_all handles an empty batch" do
      assert_empty DeploymentCorrelator.for_all([])
    end

    # Edge Cases

    test "a deployment exactly at the change point counts" do
      deployment = deployment_at(@now - 2.hours)
      finding    = finding_with_change_point(@now - 2.hours)

      assert_equal deployment, DeploymentCorrelator.for(finding)
    end

    test "the window is configurable" do
      deployment_at(@now - 20.hours)
      finding = finding_with_change_point(@now - 2.hours)

      assert_nil DeploymentCorrelator.for(finding)
      assert_not_nil DeploymentCorrelator.for(finding, window: 24.hours)
    end
  end
end
