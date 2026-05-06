require "test_helper"

class DeploymentMarkersConcernTest < ActionController::TestCase
  class TestController < ActionController::Base
    include DeploymentMarkersConcern

    attr_accessor :start_time, :end_time

    def initialize
      super
      @start_time = nil
      @end_time   = nil
    end
  end

  fixtures :rails_pulse_deployments

  setup do
    ENV["TEST_TYPE"] = "functional"
    @controller = TestController.new
    @now = Time.current
    travel_to @now
  end

  teardown do
    travel_back
  end

  # Structure Tests

  test "populate_deployment_markers sets @deployment_markers as array" do
    @controller.start_time = 3.hours.ago.to_i
    @controller.end_time   = Time.current.to_i

    @controller.send(:populate_deployment_markers)
    markers = @controller.instance_variable_get(:@deployment_markers)

    assert_kind_of Array, markers
  end

  test "populate_deployment_markers returns markers within range" do
    @controller.start_time = 3.hours.ago.to_i
    @controller.end_time   = Time.current.to_i

    @controller.send(:populate_deployment_markers)
    markers = @controller.instance_variable_get(:@deployment_markers)

    # v1_deploy (2.hours.ago) and v2_deploy (30.minutes.ago) are both in range
    assert_operator markers.length, :>=, 2
  end

  test "populate_deployment_markers excludes deployments outside range" do
    # Range that only includes v2_deploy (30 minutes ago), not v1_deploy (2 hours ago)
    @controller.start_time = 45.minutes.ago.to_i
    @controller.end_time   = Time.current.to_i

    @controller.send(:populate_deployment_markers)
    markers = @controller.instance_variable_get(:@deployment_markers)
    revisions = markers.map { |m| m[:revision] }

    assert_includes revisions, "def5678"
    refute_includes revisions, "abc1234"
  end

  test "populate_deployment_markers returns empty array when no deployments in range" do
    @controller.start_time = 5.hours.ago.to_i
    @controller.end_time   = 4.hours.ago.to_i

    @controller.send(:populate_deployment_markers)
    markers = @controller.instance_variable_get(:@deployment_markers)

    assert_empty markers
  end

  # Marker Structure Tests

  test "each marker has timestamp, revision, and started_at keys" do
    @controller.start_time = 3.hours.ago.to_i
    @controller.end_time   = Time.current.to_i

    @controller.send(:populate_deployment_markers)
    markers = @controller.instance_variable_get(:@deployment_markers)

    assert_not_empty markers
    markers.each do |marker|
      assert_includes marker.keys, :timestamp
      assert_includes marker.keys, :revision
      assert_includes marker.keys, :started_at
    end
  end

  test "marker timestamps are in milliseconds" do
    @controller.start_time = 3.hours.ago.to_i
    @controller.end_time   = Time.current.to_i

    @controller.send(:populate_deployment_markers)
    markers = @controller.instance_variable_get(:@deployment_markers)

    assert_not_empty markers
    markers.each do |marker|
      assert_operator marker[:timestamp], :>, 1_000_000_000_000
    end
  end
end
