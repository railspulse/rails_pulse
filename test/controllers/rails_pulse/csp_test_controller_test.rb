require "test_helper"

class RailsPulse::CspTestControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"
    super
  end

  # HTTP Response Tests

  test "renders HTML view successfully" do
    get rails_pulse.csp_test_path

    assert_response :success
    assert_operator response.body.length, :>, 100
  end

  test "returns JSON response for JSON format" do
    get rails_pulse.csp_test_path(format: :json)

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "ok", json["status"]
    assert_equal "CSP test endpoint working", json["message"]
  end

  test "returns correct HTML content type" do
    get rails_pulse.csp_test_path

    assert_response :success
    assert_equal "text/html; charset=utf-8", response.content_type
  end

  test "returns correct JSON content type" do
    get rails_pulse.csp_test_path(format: :json)

    assert_response :success
    assert_match "application/json", response.content_type
  end

  test "view contains CSP test content" do
    get rails_pulse.csp_test_path

    assert_response :success
    assert_includes response.body, "Content Security Policy Compliance Test"
    assert_includes response.body, "Icon Controller Test"
  end

  # CSP Header Tests

  test "sets Content-Security-Policy header" do
    get rails_pulse.csp_test_path

    assert_response :success
    assert_not_nil response.headers["Content-Security-Policy"]
  end

  test "CSP includes default-src self" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "default-src 'self'"
  end

  test "CSP includes script-src with nonce" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]

    assert_match /script-src 'self' 'nonce-[A-Za-z0-9+\/=]+'/, csp
  end

  test "CSP includes style-src with nonce" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]

    assert_match /style-src 'self' 'nonce-[A-Za-z0-9+\/=]+'/, csp
  end

  test "CSP includes img-src with data URIs" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "img-src 'self' data:"
  end

  test "CSP restricts frame-src to none" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "frame-src 'none'"
  end

  test "CSP restricts object-src to none" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "object-src 'none'"
  end

  test "CSP includes base-uri self" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "base-uri 'self'"
  end

  test "CSP includes form-action self" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "form-action 'self'"
  end

  test "CSP directives properly separated" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]
    # Multiple directives separated by semicolons
    assert_operator csp.count(";"), :>, 5
  end

  test "JSON response also sets CSP headers" do
    get rails_pulse.csp_test_path(format: :json)

    assert_response :success
    assert_not_nil response.headers["Content-Security-Policy"]
  end

  test "CSP header is properly formatted" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]
    directives = csp.split(";").map(&:strip)

    assert_operator directives.count, :>, 5
  end

  # Nonce Generation Tests

  test "generates unique nonce per request" do
    get rails_pulse.csp_test_path
    csp1 = response.headers["Content-Security-Policy"]
    nonce1 = csp1.match(/'nonce-([A-Za-z0-9+\/=]+)'/)[1]

    get rails_pulse.csp_test_path
    csp2 = response.headers["Content-Security-Policy"]
    nonce2 = csp2.match(/'nonce-([A-Za-z0-9+\/=]+)'/)[1]

    assert_not_equal nonce1, nonce2
  end

  test "nonce appears in CSP header" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]
    nonce_match = csp.match(/'nonce-([A-Za-z0-9+\/=]+)'/)

    assert_not_nil nonce_match
    assert_operator nonce_match[1].length, :>, 20
  end

  test "nonce is base64 encoded" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]
    nonce = csp.match(/'nonce-([A-Za-z0-9+\/=]+)'/)[1]

    assert_match /^[A-Za-z0-9+\/=]+$/, nonce
  end

  test "nonce is used in view script tags" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]
    nonce = csp.match(/'nonce-([A-Za-z0-9+\/=]+)'/)[1]

    assert_includes response.body, "nonce=\"#{nonce}\""
  end

  test "same nonce used for script and style directives" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]
    nonces = csp.scan(/'nonce-([A-Za-z0-9+\/=]+)'/).flatten.uniq
    # Should be same nonce in both script-src and style-src
    assert_equal 1, nonces.count
  end

  # SHA-256 Hash Tests

  test "includes documented script SHA-256 hash" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]
    # Hash from line 40
    assert_includes csp, "'sha256-ieoeWczDHkReVBsRBqaal5AFMlBtNjMzgwKvLqi/tSU='"
  end

  test "includes documented style SHA-256 hash" do
    get rails_pulse.csp_test_path

    csp = response.headers["Content-Security-Policy"]
    # Hash from line 48
    assert_includes csp, "'sha256-WAyOw4V+FqDc35lQPyRADLBWbuNK8ahvYEaQIYF1+Ps='"
  end

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
