require "test_helper"

# The dummy app (like every Rails test env) sets allow_forgery_protection =
# false, so no other controller test exercises CSRF. These do, by flipping it
# on for the duration of the test.
class RailsPulse::CsrfProtectionTest < ActionDispatch::IntegrationTest
  fixtures :rails_pulse_routes, :rails_pulse_deployments

  DEPLOY_TOKEN = "csrf-test-deploy-token".freeze

  def setup
    ENV["TEST_TYPE"] = "functional"
    @original_forgery = ActionController::Base.allow_forgery_protection
    @original_token   = RailsPulse.configuration.deployment_api_token
    ActionController::Base.allow_forgery_protection = true
    RailsPulse.configuration.deployment_api_token = DEPLOY_TOKEN
    super
  end

  def teardown
    ActionController::Base.allow_forgery_protection = @original_forgery
    RailsPulse.configuration.deployment_api_token = @original_token
    super
  end

  # Structure Tests

  test "the engine declares its own forgery protection strategy" do
    strategy = RailsPulse::ApplicationController.forgery_protection_strategy

    assert_equal ActionController::RequestForgeryProtection::ProtectionMethods::Exception, strategy
  end

  test "the strategy does not depend on the host's ActionController::Base default" do
    # A host on load_defaults < 5.2 never calls protect_from_forgery on Base.
    # Simulate that by weakening Base and checking the engine keeps its own.
    original = ActionController::Base.forgery_protection_strategy
    ActionController::Base.forgery_protection_strategy =
      ActionController::RequestForgeryProtection::ProtectionMethods::NullSession

    assert_equal ActionController::RequestForgeryProtection::ProtectionMethods::Exception,
      RailsPulse::ApplicationController.forgery_protection_strategy
  ensure
    ActionController::Base.forgery_protection_strategy = original
  end

  test "verify_authenticity_token runs before authentication" do
    filters = RailsPulse::ApplicationController._process_action_callbacks.map(&:filter)

    assert_operator filters.index(:verify_authenticity_token), :<, filters.index(:authenticate_rails_pulse_user!)
  end

  # Request Tests

  test "a state-changing request without a token is rejected" do
    route = rails_pulse_routes(:api_users)

    assert_no_changes -> { route.reload.tag_list } do
      post rails_pulse.add_tag_path("route", route.id, tag: "forged")
    end

    assert_response :unprocessable_content
  end

  test "settings mutations without a token are rejected" do
    patch rails_pulse.settings_time_range_path, params: { preset: "last_7_days" }

    assert_response :unprocessable_content
    assert_nil session[:time_range_preference]
  end

  test "a state-changing request with the page's token succeeds" do
    route = rails_pulse_routes(:api_users)

    get rails_pulse.route_path(route)

    assert_response :success
    token = css_select("meta[name=csrf-token]").first["content"]

    post rails_pulse.add_tag_path("route", route.id, tag: "legit"),
      headers: { "X-CSRF-Token" => token }

    assert_response :redirect
    assert_includes route.reload.tag_list, "legit"
  end

  test "GET requests are unaffected" do
    get rails_pulse.root_path

    assert_response :success
  end

  test "the token-authenticated deployments API stays exempt" do
    assert_difference -> { RailsPulse::Deployment.count }, 1 do
      post rails_pulse.deployments_path,
        params: { deployment: { revision: "csrf-exempt" } },
        headers: { "X-Rails-Pulse-Token" => DEPLOY_TOKEN },
        as: :json
    end

    assert_response :created
  end
end
