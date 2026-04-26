require "test_helper"

module RailsPulse
  class DeploymentTest < ActiveSupport::TestCase
    fixtures :rails_pulse_deployments

    def setup
      ENV["TEST_TYPE"] = "functional"
      super
      @now = Time.current
      travel_to @now
    end

    def teardown
      travel_back
      super
    end

    # Validations

    test "validates presence of revision" do
      deployment = Deployment.new(deployed_at: Time.current)

      refute_predicate deployment, :valid?
      assert_includes deployment.errors[:revision], "can't be blank"
    end

    test "validates presence of deployed_at" do
      deployment = Deployment.new(revision: "abc1234")

      refute_predicate deployment, :valid?
      assert_includes deployment.errors[:deployed_at], "can't be blank"
    end

    test "valid deployment saves successfully" do
      assert_difference -> { Deployment.count }, 1 do
        Deployment.create!(revision: "xyz999", deployed_at: Time.current)
      end
    end

    # Scopes

    test "for_range returns deployments within range" do
      result = Deployment.for_range(3.hours.ago, 1.minute.ago)

      assert_includes result.map(&:revision), "abc1234"
      assert_includes result.map(&:revision), "def5678"
    end

    test "for_range excludes deployments outside range" do
      result = Deployment.for_range(1.hour.ago, Time.current)

      refute_includes result.map(&:revision), "abc1234"
    end

    test "for_range returns empty when no deployments in range" do
      result = Deployment.for_range(5.hours.ago, 4.hours.ago)

      assert_empty result
    end

    test "recent orders by deployed_at desc" do
      results = Deployment.recent
      if results.size > 1
        results.each_cons(2) do |a, b|
          assert_operator a.deployed_at, :>=, b.deployed_at
        end
      end
    end

    # Methods

    test "to_chart_marker returns correct structure" do
      deployment = rails_pulse_deployments(:v1_deploy)
      marker = deployment.to_chart_marker

      assert_kind_of Hash, marker
      assert_includes marker.keys, :timestamp
      assert_includes marker.keys, :revision
      assert_includes marker.keys, :deployed_at
      assert_equal deployment.revision, marker[:revision]
      assert_equal deployment.deployed_at.to_i * 1000, marker[:timestamp]
    end

    test "to_chart_marker timestamp is in milliseconds" do
      deployment = rails_pulse_deployments(:v1_deploy)
      marker = deployment.to_chart_marker
      # Timestamps in milliseconds are > 1 trillion (year 2001+)
      assert_operator marker[:timestamp], :>, 1_000_000_000_000
    end

    test "to_chart_marker deployed_at is ISO 8601 string" do
      deployment = rails_pulse_deployments(:v1_deploy)
      marker = deployment.to_chart_marker

      assert_kind_of String, marker[:deployed_at]
      assert_match(/\d{4}-\d{2}-\d{2}T/, marker[:deployed_at])
    end

    # Edge Cases

    test "metadata_hash returns empty hash when nil" do
      deployment = rails_pulse_deployments(:v1_deploy)

      assert_empty(deployment.metadata_hash)
    end

    test "metadata_hash parses valid JSON" do
      deployment = rails_pulse_deployments(:v2_deploy)
      result = deployment.metadata_hash

      assert_kind_of Hash, result
      assert_equal "production", result["environment"]
      assert_equal "CI", result["triggered_by"]
    end

    test "metadata_hash returns empty hash for invalid JSON" do
      deployment = rails_pulse_deployments(:v1_deploy)
      deployment.metadata = "not-valid-json{"

      assert_empty(deployment.metadata_hash)
    end

    test "metadata_hash returns empty hash for blank string" do
      deployment = rails_pulse_deployments(:v1_deploy)
      deployment.metadata = ""

      assert_empty(deployment.metadata_hash)
    end

    # Ransack

    test "ransackable_attributes returns expected fields" do
      attrs = Deployment.ransackable_attributes

      assert_includes attrs, "revision"
      assert_includes attrs, "deployed_at"
      assert_includes attrs, "id"
      assert_includes attrs, "created_at"
    end

    test "ransackable_associations returns empty array" do
      assert_empty Deployment.ransackable_associations
    end
  end
end
