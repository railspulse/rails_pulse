require "test_helper"
require "rack/mock_request"
require "rack/lint"

module RailsPulse
  class StandaloneServerTest < ActiveSupport::TestCase
    SERVER_RU = File.expand_path("../../../lib/rails_pulse_server.ru", __dir__)
    TEST_SECRET = "a" * 64

    def setup
      @original_secret = ENV["SECRET_KEY_BASE"]
      ENV["SECRET_KEY_BASE"] = TEST_SECRET
      @app = build_server_app
    end

    def teardown
      ENV["SECRET_KEY_BASE"] = @original_secret
    end

    # Health Endpoint Tests

    test "health endpoint returns 200 when database is healthy" do
      RailsPulse::Tracker.stubs(:healthy?).returns(true)

      assert_equal 200, get("/health").status
    end

    test "health endpoint returns 503 when database is unhealthy" do
      RailsPulse::Tracker.stubs(:healthy?).returns(false)

      assert_equal 503, get("/health").status
    end

    test "health endpoint always returns application/json content type" do
      assert_equal "application/json", get("/health").content_type
    end

    test "health endpoint body includes all required fields" do
      body = JSON.parse(get("/health").body)

      %w[status mode database timestamp].each do |field|
        assert_includes body, field
      end
    end

    test "health endpoint mode identifies standalone dashboard" do
      assert_equal "dashboard", JSON.parse(get("/health").body)["mode"]
    end

    test "health endpoint status is ok when healthy" do
      RailsPulse::Tracker.stubs(:healthy?).returns(true)

      assert_equal "ok", JSON.parse(get("/health").body)["status"]
    end

    test "health endpoint status is unhealthy when database is unavailable" do
      RailsPulse::Tracker.stubs(:healthy?).returns(false)

      assert_equal "unhealthy", JSON.parse(get("/health").body)["status"]
    end

    test "health endpoint timestamp is a valid ISO8601 string" do
      timestamp = JSON.parse(get("/health").body)["timestamp"]

      assert_nothing_raised { Time.iso8601(timestamp) }
    end

    # Session Compatibility Tests (Rails 8.1)

    test "dashboard request does not raise NoMethodError on session.enabled?" do
      assert_nothing_raised { get("/") }
    end

    test "dashboard response sets a session cookie" do
      assert_not_nil get("/").headers["Set-Cookie"]
    end

    test "session cookie is HttpOnly and not Secure outside production" do
      cookie = get("/").headers["Set-Cookie"]

      assert_match(/httponly/i, cookie)
      assert_no_match(/;\s*secure/i, cookie)
    end

    test "session cookie is Secure in production" do
      app = with_rails_env("production") { build_server_app }

      cookie = Rack::MockRequest.new(app).get("https://pulse.example.com/").headers["Set-Cookie"]

      assert_match(/;\s*secure/i, cookie)
    end

    test "no session cookie is issued over plain HTTP in production" do
      app = with_rails_env("production") { build_server_app }

      # rack-session refuses to write a Secure cookie on a non-TLS request,
      # so the session simply never reaches the browser.
      assert_nil Rack::MockRequest.new(app).get("http://pulse.example.com/").headers["Set-Cookie"]
    end

    test "RAILS_PULSE_INSECURE_SESSION opts out of the Secure flag in production" do
      original = ENV["RAILS_PULSE_INSECURE_SESSION"]
      ENV["RAILS_PULSE_INSECURE_SESSION"] = "1"
      app = with_rails_env("production") { build_server_app }

      cookie = Rack::MockRequest.new(app).get("/").headers["Set-Cookie"]

      assert_no_match(/;\s*secure/i, cookie)
    ensure
      ENV["RAILS_PULSE_INSECURE_SESSION"] = original
    end

    # Asset Tests
    #
    # The layout links either the gem-served bundle (/rails-pulse-assets/...)
    # or, after assets:precompile, the digested copies under public/assets.
    # Neither is served by the engine itself, so the rackup must serve both.

    test "serves the gem-bundled dashboard stylesheet and scripts" do
      %w[rails-pulse.css rails-pulse.js rails-pulse-icons.js].each do |asset|
        response = lint_get("/rails-pulse-assets/#{RailsPulse::VERSION}/#{asset}")

        assert_equal 200, response.status, "expected #{asset} to be served"
        assert_operator response.body.bytesize, :>, 0
      end
    end

    test "gem-bundled assets carry immutable cache headers" do
      response = lint_get("/rails-pulse-assets/#{RailsPulse::VERSION}/rails-pulse.css")

      assert_match(/immutable/, response.headers["cache-control"])
    end

    test "serves the digested assets installed by assets:precompile" do
      destination = Rails.public_path.join("assets")
      RailsPulse::PackagedAssets.install!(destination: destination)
      digested_path = RailsPulse::PackagedAssets.url_path("rails-pulse.css")

      assert_match(%r{\A/assets/rails-pulse-[a-f0-9]{64}\.css\z}, digested_path)

      response = lint_get(digested_path)

      assert_equal 200, response.status
      assert_match(/immutable/, response.headers["cache-control"])
    ensure
      RailsPulse::PackagedAssets.uninstall!(destination: destination)
    end

    test "unknown asset paths fall through to the dashboard rather than the static server" do
      response = lint_get("/assets/does-not-exist.css")

      assert_not_equal 200, response.status
    end

    # Rack Compliance Tests
    #
    # rackup wraps the app in Rack::Lint in its development environment, so a
    # non-compliant response (e.g. a mixed-case header name) is a 500 there.

    test "dashboard and health responses pass Rack::Lint" do
      assert_nothing_raised do
        lint_get("/health")
        lint_get("/")
      end
    end

    # Server Configuration Tests

    test "falls back to the host app's secret_key_base when SECRET_KEY_BASE is not set" do
      ENV.delete("SECRET_KEY_BASE")

      app = build_server_app

      assert_not_nil Rack::MockRequest.new(app).get("/").headers["Set-Cookie"]
    end

    test "server raises when neither SECRET_KEY_BASE nor a Rails secret_key_base is available" do
      ENV.delete("SECRET_KEY_BASE")
      Rails.application.stubs(:secret_key_base).returns(nil)

      error = assert_raises(RuntimeError) { build_server_app }

      assert_match(/SECRET_KEY_BASE/, error.message)
    ensure
      Rails.application.unstub(:secret_key_base)
    end

    private

    def build_server_app
      Rack::Builder.parse_file(SERVER_RU)
    end

    # The rackup reads Rails.env once, while the middleware stack is built.
    def with_rails_env(name)
      Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new(name))
      yield
    ensure
      Rails.unstub(:env)
    end

    def get(path)
      Rack::MockRequest.new(@app).get(path)
    end

    # Rack::Lint raises on any spec violation in the request env or response.
    def lint_get(path)
      Rack::MockRequest.new(Rack::Lint.new(@app)).get(path)
    end
  end
end
