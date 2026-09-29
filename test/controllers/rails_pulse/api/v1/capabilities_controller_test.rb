require "test_helper"

module RailsPulse
  module Api
    module V1
      class CapabilitiesControllerTest < ActionDispatch::IntegrationTest
        VALID_TOKEN = "test-api-token"

        setup do
          RailsPulse.configuration.api_token = VALID_TOKEN
        end

        teardown do
          RailsPulse.configuration.api_token = nil
        end

        def get_capabilities
          get rails_pulse.api_v1_capabilities_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          JSON.parse(response.body)
        end

        # Structure Tests

        test "returns 401 without token" do
          get rails_pulse.api_v1_capabilities_path

          assert_response :unauthorized
        end

        test "identifies the installation that answered" do
          body = get_capabilities

          assert_response :success
          assert_equal RailsPulse::VERSION, body["rails_pulse_version"]
          assert_equal Rails.env.to_s, body["environment"]
          refute_nil body["application"]
        end
      end
    end
  end
end
