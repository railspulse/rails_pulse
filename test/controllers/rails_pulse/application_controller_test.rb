require "test_helper"

class RailsPulse::ApplicationControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"
    super
  end

  test "set_pagination_limit updates session and returns success" do
    patch rails_pulse_engine.pagination_limit_path, params: { limit: 25 }

    assert_response :success
    assert_equal 25, session[:pagination_limit]
    assert_equal({ "status" => "ok" }, JSON.parse(response.body))
  end

  test "set_pagination_limit sets limit directly without clamping" do
    # Test that it sets the value directly as provided
    patch rails_pulse_engine.pagination_limit_path, params: { limit: 1 }

    assert_equal 1, session[:pagination_limit]

    # Test large value is set directly
    patch rails_pulse_engine.pagination_limit_path, params: { limit: 100 }

    assert_equal 100, session[:pagination_limit]
  end

  test "set_pagination_limit handles invalid limit gracefully" do
    patch rails_pulse_engine.pagination_limit_path, params: { limit: "invalid" }

    assert_response :success
    assert_equal 0, session[:pagination_limit]  # "invalid".to_i returns 0
  end

  test "authentication is disabled by default" do
    RailsPulse.configuration.stubs(:authentication_enabled).returns(false)
    get rails_pulse_engine.root_path

    assert_response :success
  end

  test "authentication fallback with valid credentials" do
    RailsPulse.configuration.stubs(:authentication_enabled).returns(true)
    RailsPulse.configuration.stubs(:authentication_method).returns(nil)
    ENV["RAILS_PULSE_USERNAME"] = "admin"
    ENV["RAILS_PULSE_PASSWORD"] = "secret"

    get rails_pulse_engine.root_path, headers: basic_auth_headers("admin", "secret")

    assert_response :success
  end

  test "authentication fallback denies invalid credentials" do
    RailsPulse.configuration.stubs(:authentication_enabled).returns(true)
    RailsPulse.configuration.stubs(:authentication_method).returns(nil)
    ENV["RAILS_PULSE_USERNAME"] = "admin"
    ENV["RAILS_PULSE_PASSWORD"] = "secret"

    get rails_pulse_engine.root_path, headers: basic_auth_headers("admin", "wrong")

    assert_response :unauthorized
  end

  test "authentication denies access when password not set" do
    RailsPulse.configuration.stubs(:authentication_enabled).returns(true)
    RailsPulse.configuration.stubs(:authentication_method).returns(nil)
    ENV["RAILS_PULSE_USERNAME"] = "admin"
    ENV["RAILS_PULSE_PASSWORD"] = nil

    get rails_pulse_engine.root_path

    assert_response :unauthorized
  end

  private

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end

  def basic_auth_headers(username, password)
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }
  end
end
