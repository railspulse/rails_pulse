require "test_helper"

class RailsPulse::BreadcrumbsHelperTest < ActionView::TestCase
  include RailsPulse::BreadcrumbsHelper
  fixtures :rails_pulse_routes, :rails_pulse_jobs, :rails_pulse_job_runs, :rails_pulse_requests,
           :rails_pulse_exception_groups, :rails_pulse_exception_occurrences

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @route = rails_pulse_routes(:api_users)
    @job = rails_pulse_jobs(:report_job)
    @job_run = rails_pulse_job_runs(:report_run_success)
    @request_record = rails_pulse_requests(:users_request_1)
  end

  # ============================================================================
  # Helper Structure Tests
  # ============================================================================

  test "helper module is included" do
    assert_respond_to self, :breadcrumbs
  end

  # ============================================================================
  # Root Path Tests
  # ============================================================================

  test "breadcrumbs returns empty array for engine root path" do
    setup_request_path("/rails_pulse")

    crumbs = breadcrumbs

    # At the root path, there are no segments after mount point
    assert_equal 0, crumbs.length
  end

  test "breadcrumbs returns empty array when no segments after mount point" do
    setup_request_path("/rails_pulse")

    crumbs = breadcrumbs

    # When at the mount point itself, no breadcrumbs are shown
    assert_equal 0, crumbs.length
  end

  # ============================================================================
  # Simple Path Tests
  # ============================================================================

  test "breadcrumbs builds path segments after engine mount point" do
    setup_request_path("/rails_pulse/routes")

    crumbs = breadcrumbs

    assert_equal 2, crumbs.length
    assert_equal "Home", crumbs[0][:title]
    assert_equal "Routes", crumbs[1][:title]
  end

  test "breadcrumbs titleizes non-numeric segments" do
    setup_request_path("/rails_pulse/routes")

    crumbs = breadcrumbs

    assert_equal "Routes", crumbs[1][:title]
  end

  test "breadcrumbs marks last segment as current" do
    setup_request_path("/rails_pulse/routes")

    crumbs = breadcrumbs

    assert crumbs.last[:current]
    refute crumbs.first[:current]
  end

  # Resource with ID Tests

  test "breadcrumbs converts numeric segments to resource names using to_breadcrumb for Route" do
    setup_request_path("/rails_pulse/routes/#{@route.id}")

    crumbs = breadcrumbs

    assert_equal 3, crumbs.length
    assert_equal "Home", crumbs[0][:title]
    assert_equal "Routes", crumbs[1][:title]
    assert_equal @route.to_breadcrumb, crumbs[2][:title]
  end

  test "breadcrumbs converts numeric segments to resource names using to_breadcrumb for Job" do
    setup_request_path("/rails_pulse/jobs/#{@job.id}")

    crumbs = breadcrumbs

    assert_equal 3, crumbs.length
    assert_equal "Home", crumbs[0][:title]
    assert_equal "Jobs", crumbs[1][:title]
    assert_equal @job.to_breadcrumb, crumbs[2][:title]
  end

  test "breadcrumbs falls back to to_s when to_breadcrumb not available" do
    setup_request_path("/rails_pulse/requests/#{@request_record.id}")

    crumbs = breadcrumbs

    assert_equal 3, crumbs.length
    assert_equal "Home", crumbs[0][:title]
    assert_equal "Requests", crumbs[1][:title]
    # Request doesn't have to_breadcrumb, so it uses to_s which returns a formatted date
    assert_equal @request_record.to_s, crumbs[2][:title]
  end

  # Path Building Tests

  test "breadcrumbs builds correct paths for each segment" do
    setup_request_path("/rails_pulse/routes/#{@route.id}")

    crumbs = breadcrumbs

    assert_equal main_app.rails_pulse_path, crumbs[0][:path]
    assert_equal "#{main_app.rails_pulse_path.chomp('/')}/routes", crumbs[1][:path]
    assert_equal "#{main_app.rails_pulse_path.chomp('/')}/routes/#{@route.id}", crumbs[2][:path]
  end

  test "breadcrumbs builds progressive paths for deep nesting" do
    setup_request_path("/rails_pulse/routes/#{@route.id}/details")

    crumbs = breadcrumbs

    assert_equal 4, crumbs.length
    assert_equal main_app.rails_pulse_path, crumbs[0][:path]
    assert_equal "#{main_app.rails_pulse_path.chomp('/')}/routes", crumbs[1][:path]
    assert_equal "#{main_app.rails_pulse_path.chomp('/')}/routes/#{@route.id}", crumbs[2][:path]
    assert_equal "#{main_app.rails_pulse_path.chomp('/')}/routes/#{@route.id}/details", crumbs[3][:path]
  end

  # Nested Resource Tests (NEW - The key feature updated in this branch)

  test "breadcrumbs links nested collection to parent show page" do
    setup_request_path("/rails_pulse/jobs/#{@job.id}/runs/#{@job_run.id}")

    crumbs = breadcrumbs

    # Should have: Home > Jobs > GenerateReportJob > Runs > [job_run_id]
    assert_equal 5, crumbs.length
    assert_equal "Home", crumbs[0][:title]
    assert_equal "Jobs", crumbs[1][:title]
    assert_equal @job.to_breadcrumb, crumbs[2][:title]
    assert_equal "Runs", crumbs[3][:title]
    assert_equal @job_run.to_breadcrumb, crumbs[4][:title]

    # The "Runs" breadcrumb should link to the parent job show page, not /jobs/:id/runs
    assert_equal "#{main_app.rails_pulse_path.chomp('/')}/jobs/#{@job.id}", crumbs[3][:path]
  end

  test "breadcrumbs nested collection does not affect non-nested paths" do
    setup_request_path("/rails_pulse/jobs/#{@job.id}/runs")

    crumbs = breadcrumbs

    # Should have: Home > Jobs > GenerateReportJob > Runs
    assert_equal 4, crumbs.length

    runs_breadcrumb = crumbs[3]

    assert_equal "Runs", runs_breadcrumb[:title]
    # This is NOT a nested collection (no ID after "runs"), so normal path
    assert_equal "#{main_app.rails_pulse_path.chomp('/')}/jobs/#{@job.id}/runs", runs_breadcrumb[:path]
  end

  test "breadcrumbs converts numeric segments using to_breadcrumb for ExceptionGroup" do
    group = rails_pulse_exception_groups(:record_not_found)
    setup_request_path("/rails_pulse/exceptions/#{group.id}")

    crumbs = breadcrumbs

    assert_equal 3, crumbs.length
    assert_equal "Exceptions", crumbs[1][:title]
    assert_equal group.to_breadcrumb, crumbs[2][:title]
  end

  test "breadcrumbs converts nested occurrence using to_breadcrumb" do
    group = rails_pulse_exception_groups(:record_not_found)
    occurrence = rails_pulse_exception_occurrences(:occurrence_one)
    setup_request_path("/rails_pulse/exceptions/#{group.id}/occurrences/#{occurrence.id}")

    crumbs = breadcrumbs

    assert_equal 5, crumbs.length
    assert_equal group.to_breadcrumb, crumbs[2][:title]
    assert_equal "Occurrences", crumbs[3][:title]
    assert_equal occurrence.to_breadcrumb, crumbs[4][:title]
    assert_equal "#{main_app.rails_pulse_path.chomp('/')}/exceptions/#{group.id}", crumbs[3][:path]
  end

  # ============================================================================
  # Multi-Segment Mount Point Tests
  # ============================================================================

  test "breadcrumbs works when engine is mounted under a multi-segment path" do
    RailsPulse::Engine.routes.stubs(:find_script_name).returns("/backstage/devtools/rails_pulse")
    setup_request_path("/backstage/devtools/rails_pulse/routes")

    crumbs = breadcrumbs

    assert_equal 2, crumbs.length
    assert_equal "Home", crumbs[0][:title]
    assert_equal "Routes", crumbs[1][:title]
  end

  test "breadcrumbs works for resource path under a multi-segment mount point" do
    RailsPulse::Engine.routes.stubs(:find_script_name).returns("/backstage/devtools/rails_pulse")
    setup_request_path("/backstage/devtools/rails_pulse/routes/#{@route.id}")

    crumbs = breadcrumbs

    assert_equal 3, crumbs.length
    assert_equal "Home", crumbs[0][:title]
    assert_equal "Routes", crumbs[1][:title]
    assert_equal @route.to_breadcrumb, crumbs[2][:title]
  end

  # ============================================================================
  # Root Mount Point Tests (standalone server, or `mount RailsPulse::Engine => "/"`)
  # ============================================================================

  test "breadcrumbs build single-slash paths when the engine is served at root" do
    RailsPulse::Engine.routes.stubs(:find_script_name).returns("")
    setup_request_path("/routes/#{@route.id}")

    crumbs = breadcrumbs

    assert_equal [ "/", "/routes", "/routes/#{@route.id}" ], crumbs.map { |crumb| crumb[:path] }
    assert_equal [ "Home", "Routes", @route.to_breadcrumb ], crumbs.map { |crumb| crumb[:title] }
  end

  test "breadcrumbs nested collection links to the parent when served at root" do
    RailsPulse::Engine.routes.stubs(:find_script_name).returns("")
    setup_request_path("/jobs/#{@job.id}/runs/#{@job_run.id}")

    crumbs = breadcrumbs

    assert_equal "/jobs/#{@job.id}", crumbs[2][:path]
    assert_no_match(%r{\A//}, crumbs.map { |crumb| crumb[:path] }.join(" "))
  end

  test "breadcrumbs are empty at the root of a root-mounted engine" do
    RailsPulse::Engine.routes.stubs(:find_script_name).returns("")
    setup_request_path("/")

    assert_empty breadcrumbs
  end

  # Error Handling Tests

  test "breadcrumbs handles missing resources gracefully" do
    non_existent_id = 999999
    setup_request_path("/rails_pulse/routes/#{non_existent_id}")

    assert_raises ActiveRecord::RecordNotFound do
      breadcrumbs
    end
  end

  test "breadcrumbs handles path with multiple segments" do
    setup_request_path("/rails_pulse/routes/#{@route.id}/details/performance")

    crumbs = breadcrumbs

    assert_equal 5, crumbs.length
    assert_equal "Home", crumbs[0][:title]
    assert_equal "Routes", crumbs[1][:title]
    assert_equal @route.to_breadcrumb, crumbs[2][:title]
    assert_equal "Details", crumbs[3][:title]
    assert_equal "Performance", crumbs[4][:title]
  end

  private

  def setup_request_path(path)
    # Create a simple request stub with the path method
    request_stub = Struct.new(:path).new(path)
    @request = request_stub
  end

  def main_app
    Rails.application.routes.url_helpers
  end
end
