require "test_helper"

class RailsPulse::DeploymentsControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  fixtures :rails_pulse_deployments

  DEPLOY_TOKEN = "test-deploy-token"

  def setup
    ENV["TEST_TYPE"] = "functional"
    @original_token = RailsPulse.configuration.deployment_api_token
    RailsPulse.configuration.deployment_api_token = DEPLOY_TOKEN
    super
  end

  def teardown
    RailsPulse.configuration.deployment_api_token = @original_token
    super
  end

  # Inject the deployment token into every request so the fail-closed
  # guard doesn't reject them. Tests that exercise auth explicitly
  # override the token or headers as needed.
  %i[post put].each do |verb|
    define_method(verb) do |path, **opts|
      opts[:headers] = (opts[:headers] || {}).reverse_merge("X-Rails-Pulse-Token" => DEPLOY_TOKEN)
      super(path, **opts)
    end
  end

  # POST /deployments

  # Index Action Tests

  test "index responds successfully" do
    get rails_pulse.deployments_path

    assert_response :success
  end

  test "index assigns deployments newest first" do
    get rails_pulse.deployments_path

    timestamps = assigns(:table_data).map(&:started_at)

    assert_equal timestamps.sort.reverse, timestamps
  end

  test "index renders an empty state with no deployments" do
    RailsPulse::Deployment.delete_all

    get rails_pulse.deployments_path

    assert_response :success
    assert_empty assigns(:table_data)
  end

  test "the browsable pages honour dashboard authentication" do
    # The token skip covers create/finish only. If it leaked to the pages, an
    # unauthenticated visitor could read the deployment history.
    deny = proc { render plain: "Unauthorized", status: :unauthorized }
    RailsPulse.configuration.stubs(:authentication_enabled).returns(true)
    RailsPulse.configuration.stubs(:authentication_method).returns(deny)

    get rails_pulse.deployments_path

    assert_response :unauthorized
  end

  test "the API actions still authenticate by token, not by session" do
    deny = proc { render plain: "Unauthorized", status: :unauthorized }
    RailsPulse.configuration.stubs(:authentication_enabled).returns(true)
    RailsPulse.configuration.stubs(:authentication_method).returns(deny)

    post rails_pulse.deployments_path,
      params: { deployment: { revision: "tok3n" } },
      headers: { "X-Rails-Pulse-Token" => DEPLOY_TOKEN }

    assert_response :created
  end

  test "index renders deployment status" do
    get rails_pulse.deployments_path

    assert_response :success
    assert_includes response.body, "Finished"
    assert_includes response.body, "In progress"
  end

  # Show Action Tests

  test "show responds successfully" do
    deployment = rails_pulse_deployments(:v1_deploy)

    get rails_pulse.deployment_path(deployment)

    assert_response :success
    assert_equal deployment, assigns(:deployment)
  end

  test "show renders the revision" do
    deployment = rails_pulse_deployments(:v1_deploy)

    get rails_pulse.deployment_path(deployment)

    assert_includes response.body, deployment.revision
  end

  test "show renders deployment metadata" do
    deployment = rails_pulse_deployments(:v2_deploy)

    get rails_pulse.deployment_path(deployment)

    assert_includes response.body, "production"
  end

  test "show 404s for an unknown deployment" do
    get rails_pulse.deployment_path(id: 999_999)

    assert_response :not_found
  end

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
    assert_not_nil json["started_at"]
  end

  test "create sets started_at to current time when not provided" do
    freeze_time = Time.current
    travel_to freeze_time do
      post rails_pulse.deployments_path,
           params: { deployment: { revision: "sha001" } },
           as: :json
    end

    assert_response :created
    deployment = RailsPulse::Deployment.last

    assert_in_delta freeze_time.to_i, deployment.started_at.to_i, 2
  end

  test "create accepts custom started_at" do
    custom_time = 1.hour.ago.iso8601
    post rails_pulse.deployments_path,
         params: { deployment: { revision: "sha002", started_at: custom_time } },
         as: :json

    assert_response :created
    deployment = RailsPulse::Deployment.last

    assert_equal "sha002", deployment.revision
  end

  test "create accepts finished_at" do
    started = 10.minutes.ago.iso8601
    finished = 5.minutes.ago.iso8601
    post rails_pulse.deployments_path,
         params: { deployment: { revision: "sha003", started_at: started, finished_at: finished } },
         as: :json

    assert_response :created
    deployment = RailsPulse::Deployment.last

    assert_not_nil deployment.finished_at
    assert_not_nil JSON.parse(response.body)["finished_at"]
  end

  test "finished_at is nil when not provided" do
    post rails_pulse.deployments_path,
         params: { deployment: { revision: "sha004" } },
         as: :json

    assert_response :created
    assert_nil RailsPulse::Deployment.last.finished_at
  end

  test "create returns 422 when revision is missing" do
    assert_no_difference -> { RailsPulse::Deployment.count } do
      post rails_pulse.deployments_path,
           params: { deployment: { revision: "" } },
           as: :json
    end

    assert_response :unprocessable_content
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

  test "create response includes revision and started_at" do
    post rails_pulse.deployments_path,
         params: { deployment: { revision: "abc999" } },
         as: :json

    assert_response :created
    json = JSON.parse(response.body)

    assert_includes json.keys, "revision"
    assert_includes json.keys, "started_at"
    assert_includes json.keys, "finished_at"
    assert_includes json.keys, "id"
  end

  # Token Authentication

  test "create succeeds with correct token" do
    RailsPulse.configuration.deployment_api_token = "secret-token"

    post rails_pulse.deployments_path,
         params: { deployment: { revision: "tokensha1" } },
         headers: { "X-Rails-Pulse-Token" => "secret-token" },
         as: :json

    assert_response :created
  ensure
    RailsPulse.configuration.deployment_api_token = DEPLOY_TOKEN
  end

  test "create returns 401 with wrong token" do
    RailsPulse.configuration.deployment_api_token = "secret-token"

    post rails_pulse.deployments_path,
         params: { deployment: { revision: "tokensha2" } },
         headers: { "X-Rails-Pulse-Token" => "wrong-token" },
         as: :json

    assert_response :unauthorized
  ensure
    RailsPulse.configuration.deployment_api_token = DEPLOY_TOKEN
  end

  test "create returns 401 when token configured but none provided" do
    RailsPulse.configuration.deployment_api_token = "secret-token"

    post rails_pulse.deployments_path,
         params: { deployment: { revision: "tokensha3" } },
         headers: { "X-Rails-Pulse-Token" => "" },
         as: :json

    assert_response :unauthorized
  ensure
    RailsPulse.configuration.deployment_api_token = DEPLOY_TOKEN
  end

  test "create returns 401 when no token configured and auth disabled" do
    RailsPulse.configuration.deployment_api_token = nil

    # Fail closed: no token configured means no way to verify the caller,
    # even when dashboard auth is disabled.
    post rails_pulse.deployments_path,
         params: { deployment: { revision: "tokensha4" } },
         headers: {},
         as: :json

    assert_response :unauthorized
  end

  # PUT /deployments/finish

  test "finish sets finished_at on the matching deployment" do
    deployment = rails_pulse_deployments(:v2_deploy)

    assert_nil deployment.finished_at

    put rails_pulse.finish_deployments_path,
        params: { deployment: { revision: deployment.revision } },
        as: :json

    assert_response :ok
    assert_not_nil deployment.reload.finished_at
  end

  test "finish defaults finished_at to current time when not provided" do
    freeze_time = Time.current
    travel_to freeze_time do
      put rails_pulse.finish_deployments_path,
          params: { deployment: { revision: rails_pulse_deployments(:v2_deploy).revision } },
          as: :json
    end

    assert_response :ok
    assert_in_delta freeze_time.to_i, rails_pulse_deployments(:v2_deploy).reload.finished_at.to_i, 2
  end

  test "finish accepts a custom finished_at" do
    custom_time = 3.minutes.ago.iso8601

    put rails_pulse.finish_deployments_path,
        params: { deployment: { revision: rails_pulse_deployments(:v2_deploy).revision, finished_at: custom_time } },
        as: :json

    assert_response :ok
    assert_not_nil rails_pulse_deployments(:v2_deploy).reload.finished_at
  end

  test "finish returns id, revision, started_at, and finished_at" do
    deployment = rails_pulse_deployments(:v2_deploy)

    put rails_pulse.finish_deployments_path,
        params: { deployment: { revision: deployment.revision } },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)

    assert_equal "updated", json["status"]
    assert_equal deployment.id, json["id"]
    assert_equal deployment.revision, json["revision"]
    assert_includes json.keys, "started_at"
    assert_includes json.keys, "finished_at"
  end

  test "finish targets the most recent deployment when revision appears more than once" do
    older = RailsPulse::Deployment.create!(revision: "dup-sha", started_at: 2.hours.ago)
    newer = RailsPulse::Deployment.create!(revision: "dup-sha", started_at: 30.minutes.ago)

    put rails_pulse.finish_deployments_path,
        params: { deployment: { revision: "dup-sha" } },
        as: :json

    assert_response :ok
    assert_not_nil newer.reload.finished_at
    assert_nil older.reload.finished_at
  end

  test "finish returns 404 when revision is not found" do
    put rails_pulse.finish_deployments_path,
        params: { deployment: { revision: "unknown-sha" } },
        as: :json

    assert_response :not_found
    json = JSON.parse(response.body)

    assert_equal "error", json["status"]
    assert_includes json.keys, "error"
  end

  test "finish returns 400 when deployment params are missing" do
    put rails_pulse.finish_deployments_path,
        params: { deployment: {} },
        as: :json

    assert_response :bad_request
  end

  test "finish does not change the deployment count" do
    assert_no_difference -> { RailsPulse::Deployment.count } do
      put rails_pulse.finish_deployments_path,
          params: { deployment: { revision: rails_pulse_deployments(:v2_deploy).revision } },
          as: :json
    end
  end

  test "finish returns 401 with wrong token" do
    RailsPulse.configuration.deployment_api_token = "secret-token"

    put rails_pulse.finish_deployments_path,
        params: { deployment: { revision: rails_pulse_deployments(:v2_deploy).revision } },
        headers: { "X-Rails-Pulse-Token" => "wrong-token" },
        as: :json

    assert_response :unauthorized
  ensure
    RailsPulse.configuration.deployment_api_token = DEPLOY_TOKEN
  end

  test "finish succeeds with correct token" do
    RailsPulse.configuration.deployment_api_token = "secret-token"

    put rails_pulse.finish_deployments_path,
        params: { deployment: { revision: rails_pulse_deployments(:v2_deploy).revision } },
        headers: { "X-Rails-Pulse-Token" => "secret-token" },
        as: :json

    assert_response :ok
  ensure
    RailsPulse.configuration.deployment_api_token = DEPLOY_TOKEN
  end
end
