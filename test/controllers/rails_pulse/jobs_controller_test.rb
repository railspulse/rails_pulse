require "test_helper"

class RailsPulse::JobsControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @job = rails_pulse_jobs(:report_job)
  end

  # Controller Structure Tests

  test "controller includes required concerns" do
    assert_includes RailsPulse::JobsController.included_modules, TagFilterConcern
    assert_includes RailsPulse::JobsController.included_modules, TimeRangeConcern

    # Check for Pagy module (Backend in 8.x, Method in 43+)
    pagy_module = defined?(Pagy::Method) ? Pagy::Method : Pagy::Backend

    assert_includes RailsPulse::JobsController.included_modules, pagy_module
  end

  test "controller has index and show actions" do
    controller = RailsPulse::JobsController.new

    assert_respond_to controller, :index
    assert_respond_to controller, :show
  end

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::JobsController, :<, RailsPulse::ApplicationController
  end

  test "controller defines custom TIME_RANGE_OPTIONS" do
    expected_options = [
      [ "Recent", "recent" ],
      [ "Custom Range", "custom" ]
    ]

    assert_equal expected_options, RailsPulse::JobsController::TIME_RANGE_OPTIONS
  end

  # Index Action Tests

  test "index action loads successfully" do
    get rails_pulse.jobs_path

    assert_response :success
    assert_not_nil assigns(:ransack_query)
    assert_not_nil assigns(:pagy)
    assert_not_nil assigns(:jobs)
    assert_not_nil assigns(:table_data)
    assert_not_nil assigns(:available_queues)
  end

  test "index action orders jobs by runs_count desc" do
    get rails_pulse.jobs_path

    assert_response :success
    jobs = assigns(:jobs)

    # Verify jobs are ordered by runs_count desc
    if jobs.size > 1
      jobs.each_cons(2) do |current, next_job|
        assert_operator current.runs_count, :>=, next_job.runs_count
      end
    end
  end

  test "index action with ransack search by name" do
    get rails_pulse.jobs_path, params: { q: { name_cont: "Report" } }

    assert_response :success
    jobs = assigns(:jobs)

    # All returned jobs should have "Report" in the name
    assert jobs.all? { |job| job.name.include?("Report") }
  end

  test "index action with ransack search by queue_name" do
    get rails_pulse.jobs_path, params: { q: { queue_name_eq: "default" } }

    assert_response :success
    jobs = assigns(:jobs)

    # All returned jobs should have queue_name "default"
    assert jobs.all? { |job| job.queue_name == "default" }
  end

  test "index action respects pagination" do
    get rails_pulse.jobs_path, params: { limit: 10 }

    assert_response :success
    pagy = assigns(:pagy)
    jobs = assigns(:jobs)

    assert_not_nil pagy
    assert_operator jobs.size, :<=, 10
  end

  test "index action sets available_queues" do
    get rails_pulse.jobs_path

    assert_response :success
    available_queues = assigns(:available_queues)

    assert_kind_of Array, available_queues
    # Should be sorted alphabetically
    assert_equal available_queues.sort, available_queues
  end

  test "index action with custom sorting" do
    get rails_pulse.jobs_path, params: { q: { s: "name asc" } }

    assert_response :success
    jobs = assigns(:jobs)

    # Verify jobs are ordered by name asc
    if jobs.size > 1
      jobs.each_cons(2) do |current, next_job|
        assert_operator current.name, :<=, next_job.name
      end
    end
  end

  # Show Action Tests

  test "show action loads successfully" do
    get rails_pulse.job_path(@job)

    assert_response :success
    assert_not_nil assigns(:job)
    assert_not_nil assigns(:ransack_query)
    assert_not_nil assigns(:pagy)
    assert_not_nil assigns(:recent_runs)
    assert_not_nil assigns(:table_data)
    assert_not_nil assigns(:selected_time_range)
    assert_equal @job, assigns(:job)
  end

  test "show action defaults to recent mode" do
    get rails_pulse.job_path(@job)

    assert_response :success
    assert_equal "recent", assigns(:selected_time_range)
  end

  test "show action with recent mode does not filter by time" do
    get rails_pulse.job_path(@job), params: { q: { period_start_range: "recent" } }

    assert_response :success
    assert_equal "recent", assigns(:selected_time_range)
    # In recent mode, start_time and end_time should not be set
    assert_nil assigns(:start_time)
  end

  test "show action orders runs by occurred_at desc" do
    get rails_pulse.job_path(@job)

    assert_response :success
    runs = assigns(:recent_runs)

    # Verify runs are ordered by occurred_at desc
    if runs.size > 1
      runs.each_cons(2) do |current, next_run|
        assert_operator current.occurred_at, :>=, next_run.occurred_at
      end
    end
  end

  test "show action with ransack search by status" do
    get rails_pulse.job_path(@job), params: { q: { status_eq: "success" } }

    assert_response :success
    runs = assigns(:recent_runs)

    # All returned runs should have status "success"
    assert runs.all? { |run| run.status == "success" }
  end

  test "show action with ransack search by duration" do
    get rails_pulse.job_path(@job), params: { q: { duration_gteq: 300 } }

    assert_response :success
    runs = assigns(:recent_runs)

    # All returned runs should have duration >= 300
    assert runs.all? { |run| run.duration.to_f >= 300 }
  end

  test "show action respects pagination" do
    get rails_pulse.job_path(@job), params: { limit: 10 }

    assert_response :success
    pagy = assigns(:pagy)
    runs = assigns(:recent_runs)

    assert_not_nil pagy
    assert_operator runs.size, :<=, 10
  end

  test "show action with custom sorting" do
    get rails_pulse.job_path(@job), params: { q: { s: "duration asc" } }

    assert_response :success
    runs = assigns(:recent_runs)

    # Verify runs are ordered by duration asc
    if runs.size > 1
      runs.each_cons(2) do |current, next_run|
        assert_operator current.duration.to_f, :<=, next_run.duration.to_f
      end
    end
  end

  test "show action table_data matches recent_runs" do
    get rails_pulse.job_path(@job)

    assert_response :success
    assert_equal assigns(:recent_runs), assigns(:table_data)
  end

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
