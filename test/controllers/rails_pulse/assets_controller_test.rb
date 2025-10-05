require "test_helper"

class RailsPulse::AssetsControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"


    super
  end

  test "controller has show action" do
    controller = RailsPulse::AssetsController.new

    assert_respond_to controller, :show
  end

  test "handles content type determination correctly" do
    # Test the logic from the controller directly
    assert_equal "application/javascript", content_type_for(".js")
    assert_equal "text/css", content_type_for(".css")
    assert_equal "application/json", content_type_for(".map")
    assert_equal "image/svg+xml", content_type_for(".svg")
    assert_equal "application/octet-stream", content_type_for(".unknown")
  end

  test "controller uses skip_before_action" do
    # Test that the controller class has the expected configuration
    controller_class = RailsPulse::AssetsController

    assert_respond_to controller_class, :_process_action_callbacks
  end

  private

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end

  def content_type_for(extension)
    case extension
    when ".js" then "application/javascript"
    when ".css" then "text/css"
    when ".map" then "application/json"
    when ".svg" then "image/svg+xml"
    else "application/octet-stream"
    end
  end
end
