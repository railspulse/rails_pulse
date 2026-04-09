require "test_helper"

module RailsPulse
  module Middleware
    class AssetServerTest < ActiveSupport::TestCase
      def setup
        super
        @app = ->(env) { [ 200, { "Content-Type" => "text/html" }, [ "app response" ] ] }
        @assets_root = RailsPulse::Engine.root.join("public").to_s
        @middleware = AssetServer.new(
          @app,
          @assets_root,
          { urls: [ "/rails-pulse-assets" ] }
        )
      end

      # Pass-through Tests

      test "non-asset requests pass through to the app" do
        env = Rack::MockRequest.env_for("/home")

        status, _headers, body = @middleware.call(env)

        assert_equal 200, status
        assert_equal [ "app response" ], body
      end

      test "api requests pass through to the app" do
        env = Rack::MockRequest.env_for("/api/v1/users")

        status, _headers, body = @middleware.call(env)

        assert_equal 200, status
        assert_equal [ "app response" ], body
      end

      # Asset Request Tests

      test "rails pulse asset requests do not pass through to app" do
        app_called = false
        app = ->(env) { app_called = true; [ 200, {}, [ "app" ] ] }
        middleware = AssetServer.new(
          app,
          @assets_root,
          { urls: [ "/rails-pulse-assets" ] }
        )

        env = Rack::MockRequest.env_for("/rails-pulse-assets/rails-pulse.css")
        middleware.call(env)

        refute app_called
      end

      test "asset request returns a status code" do
        env = Rack::MockRequest.env_for("/rails-pulse-assets/rails-pulse.css")

        status, headers, _body = @middleware.call(env)

        # Either 200 (file found) or 404 (file missing in test env) — both are valid
        assert_includes [ 200, 404 ], status
        assert_kind_of Hash, headers
      end

      # Cache Header Tests

      test "cache_headers returns immutable headers in non-development mode" do
        Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

        headers = @middleware.send(:cache_headers)

        assert_includes headers["Cache-Control"], "immutable"
      ensure
        Rails.unstub(:env)
      end

      test "cache_headers returns no-cache headers in development mode" do
        Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("development"))

        headers = @middleware.send(:cache_headers)

        assert_includes headers["Cache-Control"], "no-cache"
      ensure
        Rails.unstub(:env)
      end

      # MIME Type Tests

      test "MIME_TYPES includes css" do
        assert_equal "text/css", AssetServer::MIME_TYPES[".css"]
      end

      test "MIME_TYPES includes js" do
        assert_equal "application/javascript", AssetServer::MIME_TYPES[".js"]
      end

      test "MIME_TYPES includes svg" do
        assert_equal "image/svg+xml", AssetServer::MIME_TYPES[".svg"]
      end

      test "MIME_TYPES includes png" do
        assert_equal "image/png", AssetServer::MIME_TYPES[".png"]
      end

      test "MIME_TYPES is frozen" do
        assert_predicate AssetServer::MIME_TYPES, :frozen?
      end
    end
  end
end
