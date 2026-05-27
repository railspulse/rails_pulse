require "test_helper"
require "rack/session/cookie"
require "rack/mock_request"
require "rails_pulse/rack_compat"

module RailsPulse
  class RackCompatTest < ActiveSupport::TestCase
    # Rails 8.1 Tests

    test "dashboard rack stack survives Rails 8.1 Flash session.enabled? check" do
      flash_checker = lambda do |env|
        env["rack.session"].enabled?
        [ 200, {}, [ "ok" ] ]
      end

      app = Rack::Session::Cookie.new(flash_checker,
        key: "rails_pulse_session",
        secret: "a" * 64,
        same_site: :lax,
        max_age: 86400
      )

      env = Rack::MockRequest.env_for("/rails_pulse")
      status, _headers, _body = app.call(env)

      assert_equal 200, status
    end

    test "Rack session enabled? returns true indicating session is active" do
      session = Rack::Session::Abstract::SessionHash.new(nil, {})

      assert session.enabled?
    end
  end
end
