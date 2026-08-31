require "test_helper"

class RailsPulse::FindingsControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  fixtures :rails_pulse_findings, :rails_pulse_routes, :rails_pulse_deployments

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @finding = rails_pulse_findings(:open_route_regression)
  end

  # Index Action Tests

  test "index responds successfully" do
    get rails_pulse.findings_path

    assert_response :success
  end

  test "index assigns table data and pagination" do
    get rails_pulse.findings_path

    assert_not_nil assigns(:table_data)
    assert_not_nil assigns(:pagination)
  end

  test "index defaults to open findings" do
    get rails_pulse.findings_path

    statuses = assigns(:table_data).map(&:status).uniq

    assert_equal [ "open" ], statuses
  end

  test "index shows all statuses when the filter is blank" do
    get rails_pulse.findings_path, params: { q: { status_eq: "" } }

    statuses = assigns(:table_data).map(&:status).uniq

    assert_includes statuses, "resolved"
  end

  test "index filters by severity" do
    get rails_pulse.findings_path, params: { q: { status_eq: "", severity_eq: "critical" } }

    severities = assigns(:table_data).map(&:severity).uniq

    assert_equal [ "critical" ], severities
  end

  test "index assigns correlated deployments" do
    get rails_pulse.findings_path

    assert_not_nil assigns(:deployments)
  end

  test "index renders an empty state with no findings" do
    RailsPulse::Finding.delete_all

    get rails_pulse.findings_path

    assert_response :success
    assert_empty assigns(:table_data)
  end

  # Show Action Tests

  test "show responds successfully" do
    get rails_pulse.finding_path(@finding)

    assert_response :success
  end

  test "show assigns the finding and resolves its subject label" do
    get rails_pulse.finding_path(@finding)

    assert_equal @finding, assigns(:finding)
    # The finding points at a real route, so the page names the path rather
    # than falling back to "Route #id".
    assert_includes response.body, "/api/users"
  end

  test "show renders a finding whose subject has been cleaned up" do
    # Retention can delete a route while a finding about it is still open.
    orphan = RailsPulse::Finding.create!(
      fingerprint:       SecureRandom.hex(32),
      kind:              "performance_regression",
      subject_type:      "RailsPulse::Route",
      subject_id:        999_999,
      metric:            "p95",
      severity:          "warning",
      status:            "open",
      baseline_value:    100.0,
      current_value:     400.0,
      delta:             300.0,
      ratio:             4.0,
      first_detected_at: 1.day.ago,
      last_detected_at:  1.hour.ago,
      detection_count:   1
    )

    get rails_pulse.finding_path(orphan)

    assert_response :success
  end

  test "show renders a finding with no change point" do
    finding = rails_pulse_findings(:acknowledged_error_rate_regression)

    get rails_pulse.finding_path(finding)

    assert_response :success
    assert_includes response.body, "No change point"
  end

  # Update Action Tests

  test "acknowledging an open finding" do
    patch rails_pulse.finding_path(@finding, status: "acknowledged")

    assert_redirected_to rails_pulse.finding_path(@finding)
    assert_equal "acknowledged", @finding.reload.status
  end

  test "reopening an acknowledged finding" do
    finding = rails_pulse_findings(:acknowledged_error_rate_regression)

    patch rails_pulse.finding_path(finding, status: "open")

    assert_equal "open", finding.reload.status
  end

  test "an unknown status is rejected" do
    patch rails_pulse.finding_path(@finding, status: "banana")

    assert_redirected_to rails_pulse.finding_path(@finding)
    assert_equal "open", @finding.reload.status
  end

  test "resolving by hand is not offered" do
    # Findings resolve when detection stops seeing them; a manual resolve would
    # be contradicted by the next run.
    patch rails_pulse.finding_path(@finding, status: "resolved")

    assert_equal "open", @finding.reload.status
  end
end
