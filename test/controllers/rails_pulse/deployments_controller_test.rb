require "test_helper"

class RailsPulse::DeploymentsControllerTest < ActionDispatch::IntegrationTest
  fixtures :rails_pulse_deployments

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
  end

  # POST /deployments

  test "create records deployment and returns 201" do
    assert_difference -> { RailsPulse::Deployment.count }, 1 do
      post rails_pulse.deployments_path,
           params: { deployment: { revision: "newsha123" } },
           as: :json
    end

    assert_response :created
    json = JSON.parse(response.body)

    assert_equal "created", json["status"]
    assert_equal "newsha123", json["revision"]
    assert_not_nil json["id"]
    assert_not_nil json["deployed_at"]
  end

  test "create sets deployed_at to current time when not provided" do
    freeze_time = Time.current
    travel_to freeze_time do
      post rails_pulse.deployments_path,
           params: { deployment: { revision: "sha001" } },
           as: :json
    end

    assert_response :created
    deployment = RailsPulse::Deployment.last

    assert_in_delta freeze_time.to_i, deployment.deployed_at.to_i, 2
  end

  test "create accepts custom deployed_at" do
    custom_time = 1.hour.ago.iso8601
    post rails_pulse.deployments_path,
         params: { deployment: { revision: "sha002", deployed_at: custom_time } },
         as: :json

    assert_response :created
    deployment = RailsPulse::Deployment.last

    assert_equal "sha002", deployment.revision
  end

  test "create returns 422 when revision is missing" do
    assert_no_difference -> { RailsPulse::Deployment.count } do
      post rails_pulse.deployments_path,
           params: { deployment: { revision: "" } },
           as: :json
    end

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)

    assert_equal "error", json["status"]
    assert_not_empty json["errors"]
  end

  test "create returns 400 when deployment params are missing" do
    assert_no_difference -> { RailsPulse::Deployment.count } do
      post rails_pulse.deployments_path,
           params: { deployment: {} },
           as: :json
    end

    assert_response :bad_request
  end

  test "create accepts metadata hash" do
    post rails_pulse.deployments_path,
         params: { deployment: { revision: "sha999", metadata: { environment: "production", triggered_by: "github-actions" } } },
         as: :json

    assert_response :created
    deployment = RailsPulse::Deployment.last

    assert_equal "production", deployment.metadata_hash["environment"]
    assert_equal "github-actions", deployment.metadata_hash["triggered_by"]
  end

  test "create response includes revision and deployed_at" do
    post rails_pulse.deployments_path,
         params: { deployment: { revision: "abc999" } },
         as: :json

    assert_response :created
    json = JSON.parse(response.body)

    assert_includes json.keys, "revision"
    assert_includes json.keys, "deployed_at"
    assert_includes json.keys, "id"
  end
end
