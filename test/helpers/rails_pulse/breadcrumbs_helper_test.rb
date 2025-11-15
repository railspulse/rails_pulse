require "test_helper"

class RailsPulse::BreadcrumbsHelperTest < ActionView::TestCase
  include RailsPulse::BreadcrumbsHelper
  fixtures :rails_pulse_routes, :rails_pulse_jobs, :rails_pulse_job_runs, :rails_pulse_requests

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @route = rails_pulse_routes(:api_users)
    @job = rails_pulse_jobs(:report_job)
    @job_run = rails_pulse_job_runs(:report_run_success)
    @request_record = rails_pulse_requests(:users_request_1)
  end

  # Helper Structure Tests

  test "helper module is included" do
    assert_respond_to self, :breadcrumbs
  end

  # Root Path Tests

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

  # Simple Path Tests

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
    assert_equal @route.path, crumbs[2][:title]
  end

  test "breadcrumbs converts numeric segments to resource names using to_breadcrumb for Job" do
    setup_request_path("/rails_pulse/jobs/#{@job.id}")

    crumbs = breadcrumbs

    assert_equal 3, crumbs.length
    assert_equal "Home", crumbs[0][:title]
    assert_equal "Jobs", crumbs[1][:title]
    assert_equal @job.name, crumbs[2][:title]
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
    assert_equal @job.name, crumbs[2][:title]
    assert_equal "Runs", crumbs[3][:title]
    assert_equal @job_run.id.to_s, crumbs[4][:title]

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
    assert_equal @route.path, crumbs[2][:title]
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
