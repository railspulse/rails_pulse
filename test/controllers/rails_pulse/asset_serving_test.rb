require "test_helper"

# Host-setup matrix for dashboard assets. Covers:
#   - middleware fallback (no packaged manifest)
#   - packaged public/assets (post-precompile)
#   - CDN via asset_host
#   - CDN-only CSP (no 'self' on script/style/img)
#
# Re-run with:
#   DB=sqlite3 bundle exec rails test test/controllers/rails_pulse/asset_serving_test.rb
class RailsPulse::AssetServingTest < ActionDispatch::IntegrationTest
  fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_jobs, :rails_pulse_summaries

  DASHBOARD_FILES = %w[rails-pulse.css rails-pulse.js rails-pulse-icons.js].freeze
  CDN_HOST = "https://cdn.example.com"
  TEST_CSP_NONCE = "test-nonce"
  ASSET_LOCK = Rails.root.join("tmp/rails_pulse_asset_serving.lock")

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    RailsPulse::Engine.routes.url_helpers.root_path
    acquire_asset_lock
    RailsPulse::PackagedAssets.uninstall!
    RailsPulse::PackagedAssets.reset!
  end

  def teardown
    RailsPulse::PackagedAssets.uninstall!
    RailsPulse::PackagedAssets.reset!
    release_asset_lock
    super
  end

  # Middleware fallback (no packaged manifest)

  test "dashboard HTML uses versioned origin paths and those files are reachable" do
    html = request_dashboard_html

    DASHBOARD_FILES.each do |name|
      path = versioned_asset(name)

      assert_includes html, path
      assert_asset_ok path
    end
  end

  test "asset_host does not rewrite dashboard asset URLs" do
    html = request_dashboard_html(asset_host: CDN_HOST)

    refute_includes html, "cdn.example.com"

    DASHBOARD_FILES.each do |name|
      path = versioned_asset(name)

      assert_includes html, path
      assert_asset_ok path
    end
  end

  test "stylesheet_link_tag would send the same path to the CDN" do
    with_asset_host(CDN_HOST) do
      rewritten = ActionController::Base.helpers.stylesheet_link_tag(versioned_asset("rails-pulse.css"))

      assert_includes rewritten, "cdn.example.com"
      assert_includes rewritten, versioned_asset("rails-pulse.css")
    end
  end

  test "setup screen logo stays on origin when asset_host is set" do
    RailsPulse::Summary.delete_all

    html = request_dashboard_html(asset_host: CDN_HOST)
    logo = versioned_asset("rails-pulse-logo.png")

    assert_includes html, logo
    refute_includes html, "cdn.example.com"
    assert_asset_ok logo
  end

  test "unversioned asset URLs still resolve" do
    get "/rails-pulse-assets/rails-pulse.css"

    assert_response :success
  end

  test "a previous gem version in the path still serves current files" do
    get "/rails-pulse-assets/0.0.1/rails-pulse.css"

    assert_response :success
    assert_equal "text/css", response.content_type
  end

  # Packaged public/assets (after assets:precompile / install_assets)

  test "packaged assets are addressed on the CDN when asset_host is set" do
    RailsPulse::PackagedAssets.install!
    html = request_dashboard_html(asset_host: CDN_HOST)

    assert_includes html, "cdn.example.com/assets/rails-pulse-"
    refute_includes html, versioned_asset("rails-pulse.css")
    refute_includes html, versioned_asset("rails-pulse.js")
  end

  test "packaged assets use origin /assets URLs when asset_host is unset" do
    RailsPulse::PackagedAssets.install!
    html = request_dashboard_html
    css = digested_asset_url(html, "rails-pulse.css")

    assert_match %r{\A/assets/rails-pulse-[a-f0-9]{64}\.css\z}, css
    refute_includes html, versioned_asset("rails-pulse.css")
    assert_asset_ok css
  end

  test "setup screen logo is addressed on the CDN once assets are packaged" do
    RailsPulse::PackagedAssets.install!
    RailsPulse::Summary.delete_all

    html = request_dashboard_html(asset_host: CDN_HOST)

    assert_match %r{#{Regexp.escape(CDN_HOST)}/assets/rails-pulse-logo-[a-f0-9]{64}\.png}, html
    refute_includes html, versioned_asset("rails-pulse-logo.png")
  end

  # CDN-only CSP (no 'self' on script-src / style-src / img-src)

  test "packaged CDN URLs and the inline theme nonce satisfy a CDN-only CSP" do
    RailsPulse::PackagedAssets.install!
    html = nil
    csp = nil

    with_cdn_only_csp do
      html = request_dashboard_html(asset_host: CDN_HOST)
      csp = response.headers["Content-Security-Policy"]
    end

    assert_predicate csp, :present?, "host CSP header should be present"
    assert_includes csp, "script-src #{CDN_HOST}"
    refute_match(/script-src[^;]*'self'/, csp)
    assert_includes csp, "'nonce-#{TEST_CSP_NONCE}'"

    DASHBOARD_FILES.each do |name|
      url = digested_asset_url(html, name)

      assert_match %r{\A#{Regexp.escape(CDN_HOST)}/assets/rails-pulse}, url, "#{name} should be on the CDN"
      refute_includes url, "/rails-pulse-assets/"
    end

    inline = Nokogiri::HTML(html).at_css("script:not([src])")

    assert inline, "theme bootstrap script should be present"
    assert_equal TEST_CSP_NONCE, inline["nonce"]
  end

  test "unpackaged middleware URLs would be blocked by a CDN-only CSP" do
    RailsPulse::PackagedAssets.uninstall!

    html = nil
    csp = nil

    with_cdn_only_csp do
      html = request_dashboard_html(asset_host: CDN_HOST)
      csp = response.headers["Content-Security-Policy"]
    end

    css = versioned_asset("rails-pulse.css")

    assert_includes html, css
    refute_includes html, "cdn.example.com"
    assert_includes csp, "script-src #{CDN_HOST}"
    refute_match(/script-src[^;]*'self'/, csp)
    refute_match(%r{\A#{Regexp.escape(CDN_HOST)}}, css)
  end

  private

  def acquire_asset_lock
    FileUtils.mkdir_p(ASSET_LOCK.dirname)
    @asset_lock = File.open(ASSET_LOCK, File::RDWR | File::CREAT, 0644)
    @asset_lock.flock(File::LOCK_EX)
  end

  def release_asset_lock
    return unless @asset_lock

    @asset_lock.flock(File::LOCK_UN)
    @asset_lock.close
  ensure
    @asset_lock = nil
  end

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end

  def versioned_asset(name)
    "/rails-pulse-assets/#{RailsPulse::VERSION}/#{name}"
  end

  def digested_asset_url(html, logical_name)
    ext = File.extname(logical_name)
    base = File.basename(logical_name, ext)
    match = html.match(%r{(?:https://[^/"'\s]+)?/assets/#{Regexp.escape(base)}-[a-f0-9]{64}#{Regexp.escape(ext)}})

    assert match, "HTML did not include a digested URL for #{logical_name}"
    match[0]
  end

  def with_cdn_only_csp
    env = Rails.application.env_config
    config = Rails.application.config
    previous = {
      policy: env["action_dispatch.content_security_policy"],
      nonce_generator: env["action_dispatch.content_security_policy_nonce_generator"],
      nonce_directives: env["action_dispatch.content_security_policy_nonce_directives"],
      config_nonce_generator: config.content_security_policy_nonce_generator,
      config_nonce_directives: config.content_security_policy_nonce_directives
    }

    env["action_dispatch.content_security_policy"] = ActionDispatch::ContentSecurityPolicy.new do |policy|
      policy.default_src :none
      policy.script_src CDN_HOST
      policy.style_src CDN_HOST, :unsafe_inline
      policy.img_src CDN_HOST, :data
      policy.connect_src :self
      policy.font_src CDN_HOST
      policy.form_action :self
    end
    generator = ->(_request) { TEST_CSP_NONCE }
    env["action_dispatch.content_security_policy_nonce_generator"] = generator
    env["action_dispatch.content_security_policy_nonce_directives"] = %w[script-src]
    config.content_security_policy_nonce_generator = generator
    config.content_security_policy_nonce_directives = %w[script-src]

    yield
  ensure
    env["action_dispatch.content_security_policy"] = previous[:policy]
    env["action_dispatch.content_security_policy_nonce_generator"] = previous[:nonce_generator]
    env["action_dispatch.content_security_policy_nonce_directives"] = previous[:nonce_directives]
    config.content_security_policy_nonce_generator = previous[:config_nonce_generator]
    config.content_security_policy_nonce_directives = previous[:config_nonce_directives]
  end

  def request_dashboard_html(asset_host: nil)
    with_asset_host(asset_host) do
      get rails_pulse.root_path

      assert_response :success
      response.body
    end
  end

  def assert_asset_ok(path)
    get path

    assert_response :success, "#{path} returned #{response.status}"
  end

  def with_asset_host(host)
    previous_app = Rails.application.config.asset_host
    previous_ac = ActionController::Base.config.asset_host

    Rails.application.config.asset_host = host
    Rails.application.config.action_controller.asset_host = host
    ActionController::Base.config.asset_host = host

    yield
  ensure
    Rails.application.config.asset_host = previous_app
    Rails.application.config.action_controller.asset_host = previous_app
    ActionController::Base.config.asset_host = previous_ac
  end
end
