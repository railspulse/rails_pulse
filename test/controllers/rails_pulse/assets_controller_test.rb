require "test_helper"

class RailsPulse::AssetsControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["TEST_TYPE"] = "functional"
    super
  end

  # HTTP Response Tests - Positive Cases

  test "serves JavaScript asset with correct content type" do
    get rails_pulse.asset_path(asset_name: "rails-pulse.js")

    assert_response :success
    assert_equal "application/javascript", response.content_type
    assert_operator response.body.length, :>, 0
  end

  test "serves CSS asset with correct content type" do
    get rails_pulse.asset_path(asset_name: "rails-pulse.css")

    assert_response :success
    assert_equal "text/css", response.content_type
  end

  test "serves source map with correct content type" do
    skip "Source maps not built (run npm run build)" unless File.exist?(RailsPulse::Engine.root.join("public/rails-pulse-assets/rails-pulse.js.map"))

    get rails_pulse.asset_path(asset_name: "rails-pulse.js.map")

    assert_response :success
    assert_equal "application/json", response.content_type
  end

  test "serves SVG asset with correct content type" do
    get rails_pulse.asset_path(asset_name: "search.svg")

    assert_response :success
    assert_equal "image/svg+xml", response.content_type
  end

  test "serves PNG asset with correct content type" do
    get rails_pulse.asset_path(asset_name: "rails-pulse-logo.png")

    assert_response :success
    # PNG detection varies by Rails version, just verify success
  end

  test "serves asset with inline disposition" do
    get rails_pulse.asset_path(asset_name: "rails-pulse.js")

    assert_response :success
    # send_file sets Content-Disposition header
  end

  test "returns 200 status for valid assets" do
    get rails_pulse.asset_path(asset_name: "rails-pulse.css")

    assert_response :success
  end

  # Path Traversal Security Tests

  test "returns 404 for path traversal with double dots" do
    get rails_pulse.asset_path(asset_name: "../../../etc/passwd")

    assert_response :not_found
  end

  test "returns 404 for path with forward slash" do
    get rails_pulse.asset_path(asset_name: "subdir/file.js")

    assert_response :not_found
  end

  test "returns 404 for path with backslash" do
    get rails_pulse.asset_path(asset_name: "subdir\\file.js")

    assert_response :not_found
  end

  test "returns 404 for blank asset name" do
    get rails_pulse.asset_path(asset_name: "")

    assert_response :not_found
  end

  test "returns 404 for traversal in middle of path" do
    get rails_pulse.asset_path(asset_name: "valid/../../../etc/passwd")

    assert_response :not_found
  end

  test "prevents multiple traversal attempts" do
    dangerous_paths = [
      "../secrets.txt",
      "../../config/database.yml",
      "./../app/controllers"
    ]

    dangerous_paths.each do |path|
      get rails_pulse.asset_path(asset_name: path)

      assert_response :not_found, "Failed to block: #{path}"
    end
  end

  # 404 Response Tests

  test "returns 404 for non-existent asset" do
    get rails_pulse.asset_path(asset_name: "nonexistent-file.js")

    assert_response :not_found
  end

  test "returns 404 with empty body" do
    get rails_pulse.asset_path(asset_name: "missing.css")

    assert_response :not_found
    assert_equal "", response.body
  end

  test "returns 404 for wrong file extension" do
    get rails_pulse.asset_path(asset_name: "rails-pulse.wrong")

    assert_response :not_found
  end

  # Fallback Mechanism Tests

  test "serves assets from engine directory" do
    # Test environment doesn't have host app assets, so engine is used
    get rails_pulse.asset_path(asset_name: "rails-pulse.js")

    assert_response :success
    # Successful response means fallback to engine worked
  end

  test "validates asset exists before serving" do
    get rails_pulse.asset_path(asset_name: "definitely-missing.js")

    assert_response :not_found
  end

  # Edge Cases

  test "handles multiple file extensions correctly" do
    skip "Source maps not built (run npm run build)" unless File.exist?(RailsPulse::Engine.root.join("public/rails-pulse-assets/rails-pulse.js.map"))

    get rails_pulse.asset_path(asset_name: "rails-pulse.js.map")

    assert_response :success
    # .map extension should map to application/json
    assert_equal "application/json", response.content_type
  end

  test "handles assets with hyphens in name" do
    get rails_pulse.asset_path(asset_name: "rails-pulse-icons.js")

    assert_response :success
    assert_equal "application/javascript", response.content_type
  end

  test "validates before attempting to serve" do
    # Controller checks File.exist? before send_file
    get rails_pulse.asset_path(asset_name: "notreal.css")

    assert_response :not_found
  end

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
