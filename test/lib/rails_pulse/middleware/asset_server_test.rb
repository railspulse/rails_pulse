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

      test "versioned asset path serves the same file as the unversioned path" do
        env = Rack::MockRequest.env_for("/rails-pulse-assets/#{RailsPulse::VERSION}/rails-pulse.css")

        status, _headers, _body = @middleware.call(env)

        assert_equal 200, status
      end

      test "unversioned asset path still serves files" do
        env = Rack::MockRequest.env_for("/rails-pulse-assets/rails-pulse.css")

        status, _headers, _body = @middleware.call(env)

        assert_equal 200, status
      end

      # Cache Header Tests

      test "cache_headers returns immutable headers in non-development mode" do
        Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

        headers = @middleware.send(:cache_headers)

        assert_includes headers["cache-control"], "immutable"
      ensure
        Rails.unstub(:env)
      end

      test "cache_headers returns no-cache headers in development mode" do
        Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("development"))

        headers = @middleware.send(:cache_headers)

        assert_includes headers["cache-control"], "no-cache"
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

      # Exception Handling Tests

      test "call rescues exceptions and falls back to app" do
        # Mock Rack::Static#call to raise an exception
        Rack::Static.any_instance.stubs(:call).raises(StandardError.new("Asset error"))

        # Capture log messages
        log_messages = []
        test_logger = Object.new
        test_logger.define_singleton_method(:debug) { |msg| log_messages << [ :debug, msg ] }
        test_logger.define_singleton_method(:error) { |msg| log_messages << [ :error, msg ] }
        test_logger.define_singleton_method(:debug?) { false }

        RailsPulse.stubs(:logger).returns(test_logger)

        env = Rack::MockRequest.env_for("/rails-pulse-assets/test.css")

        status, _headers, body = @middleware.call(env)

        # Should fall back to app
        assert_equal 200, status
        assert_equal [ "app response" ], body

        # Verify error was logged
        assert log_messages.any? { |level, msg| level == :error && msg.include?("Error serving asset") }

        Rack::Static.any_instance.unstub(:call)
        RailsPulse.unstub(:logger)
      end

      test "call logs error message when exception occurs" do
        Rack::Static.any_instance.stubs(:call).raises(StandardError.new("Test error"))

        log_messages = []
        test_logger = Object.new
        test_logger.define_singleton_method(:debug) { |msg| log_messages << [ :debug, msg ] }
        test_logger.define_singleton_method(:error) { |msg| log_messages << [ :error, msg ] }
        test_logger.define_singleton_method(:debug?) { false }

        RailsPulse.stubs(:logger).returns(test_logger)

        env = Rack::MockRequest.env_for("/rails-pulse-assets/test.css")
        @middleware.call(env)

        # Verify error message logged
        assert log_messages.any? { |level, msg| level == :error && msg.include?("Test error") }

        Rack::Static.any_instance.unstub(:call)
        RailsPulse.unstub(:logger)
      end

      test "call logs error backtrace when debug is enabled" do
        error = StandardError.new("Test error")
        error.set_backtrace([ "line 1", "line 2" ])

        Rack::Static.any_instance.stubs(:call).raises(error)

        log_messages = []
        test_logger = Object.new
        test_logger.define_singleton_method(:debug) { |msg| log_messages << [ :debug, msg ] }
        test_logger.define_singleton_method(:error) { |msg| log_messages << [ :error, msg ] }
        test_logger.define_singleton_method(:debug?) { true }

        RailsPulse.stubs(:logger).returns(test_logger)

        env = Rack::MockRequest.env_for("/rails-pulse-assets/test.css")
        @middleware.call(env)

        # Verify backtrace logged
        assert log_messages.any? { |level, msg| level == :error && msg.include?("line 1") }

        Rack::Static.any_instance.unstub(:call)
        RailsPulse.unstub(:logger)
      end

      # Cache Headers for Non-200 Responses

      test "404 response does not receive immutable cache headers" do
        Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

        # Mock Rack::Static to return 404
        Rack::Static.any_instance.stubs(:call).returns([ 404, {}, [ "Not found" ] ])

        log_messages = []
        test_logger = Object.new
        test_logger.define_singleton_method(:debug) { |msg| log_messages << [ :debug, msg ] }
        test_logger.define_singleton_method(:warn) { |msg| log_messages << [ :warn, msg ] }

        RailsPulse.stubs(:logger).returns(test_logger)

        env = Rack::MockRequest.env_for("/rails-pulse-assets/missing.css")
        status, headers, _body = @middleware.call(env)

        assert_equal 404, status
        refute_includes headers.to_s, "immutable"

        Rack::Static.any_instance.unstub(:call)
        Rails.unstub(:env)
        RailsPulse.unstub(:logger)
      end

      test "500 response does not receive immutable cache headers" do
        Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

        # Mock Rack::Static to return 500
        Rack::Static.any_instance.stubs(:call).returns([ 500, {}, [ "Server error" ] ])

        RailsPulse.stubs(:logger).returns(Object.new.tap { |l| l.define_singleton_method(:debug) { |_| } })

        env = Rack::MockRequest.env_for("/rails-pulse-assets/error.css")
        status, headers, _body = @middleware.call(env)

        assert_equal 500, status
        refute_includes headers.to_s, "immutable"

        Rack::Static.any_instance.unstub(:call)
        Rails.unstub(:env)
        RailsPulse.unstub(:logger)
      end

      # Logging Methods Tests

      test "log_missing_asset logs warning with path" do
        log_messages = []
        test_logger = Object.new
        test_logger.define_singleton_method(:warn) { |msg| log_messages << [ :warn, msg ] }

        RailsPulse.stubs(:logger).returns(test_logger)

        @middleware.send(:log_missing_asset, "/rails-pulse-assets/missing.css")

        assert log_messages.any? { |level, msg| level == :warn && msg.include?("Asset not found") }
        assert log_messages.any? { |level, msg| msg.include?("/rails-pulse-assets/missing.css") }

        RailsPulse.unstub(:logger)
      end

      test "log_asset_error logs error message and path" do
        log_messages = []
        test_logger = Object.new
        test_logger.define_singleton_method(:error) { |msg| log_messages << [ :error, msg ] }
        test_logger.define_singleton_method(:debug?) { false }

        RailsPulse.stubs(:logger).returns(test_logger)

        error = StandardError.new("Test error")
        @middleware.send(:log_asset_error, "/rails-pulse-assets/test.css", error)

        assert log_messages.any? { |level, msg| level == :error && msg.include?("Error serving asset") }
        assert log_messages.any? { |level, msg| msg.include?("/rails-pulse-assets/test.css") }
        assert log_messages.any? { |level, msg| msg.include?("Test error") }

        RailsPulse.unstub(:logger)
      end

      # rails_pulse_asset_request? Edge Cases

      test "rails_pulse_asset_request? returns false for nil PATH_INFO" do
        env = { "PATH_INFO" => nil }

        refute @middleware.send(:rails_pulse_asset_request?, env)
      end

      test "rails_pulse_asset_request? returns false for empty PATH_INFO" do
        env = { "PATH_INFO" => "" }

        refute @middleware.send(:rails_pulse_asset_request?, env)
      end

      test "rails_pulse_asset_request? returns true for path with trailing slash only" do
        env = { "PATH_INFO" => "/rails-pulse-assets/" }

        assert @middleware.send(:rails_pulse_asset_request?, env)
      end

      test "rails_pulse_asset_request? returns false for similar but different prefix" do
        env = { "PATH_INFO" => "/rails-pulse-assets-fake/test.css" }

        refute @middleware.send(:rails_pulse_asset_request?, env)
      end

      test "rails_pulse_asset_request? returns true for valid asset path" do
        env = { "PATH_INFO" => "/rails-pulse-assets/test.css" }

        assert @middleware.send(:rails_pulse_asset_request?, env)
      end
    end
  end
end
