require "test_helper"

class RailsPulse::CspTestControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"


    super
  end

  test "controller has show action" do
    controller = RailsPulse::CspTestController.new

    assert_respond_to controller, :show
  end

  test "controller has CSP configuration methods" do
    controller = RailsPulse::CspTestController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :set_strict_csp
    assert_includes private_methods, :request_nonce
  end

  test "generates secure nonce" do
    controller = RailsPulse::CspTestController.new
    nonce1 = controller.send(:request_nonce)
    nonce2 = controller.send(:request_nonce)

    # Should be the same within one request
    assert_equal nonce1, nonce2

    # Should be a reasonable length
    assert_operator nonce1.length, :>, 20
  end

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::CspTestController, :<, RailsPulse::ApplicationController
  end

  private

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end
end
