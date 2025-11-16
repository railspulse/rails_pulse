require "test_helper"

class RailsPulse::JobRunsControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @job = rails_pulse_jobs(:report_job)
    @run = rails_pulse_job_runs(:report_run_retried)
  end

  test "controller includes required concerns" do
    assert_includes RailsPulse::JobRunsController.included_modules, TagFilterConcern

    # Check for Pagy module (Backend in 8.x, Method in 43+)
    pagy_module = defined?(Pagy::Method) ? Pagy::Method : Pagy::Backend

    assert_includes RailsPulse::JobRunsController.included_modules, pagy_module
  end

  test "controller has index and show actions" do
    controller = RailsPulse::JobRunsController.new

    assert_respond_to controller, :index
    assert_respond_to controller, :show
  end

  # Index Action Tests
  test "index action loads successfully" do
    get rails_pulse.job_runs_path(@job)

    assert_response :success
    assert_not_nil assigns(:job)
    assert_not_nil assigns(:ransack_query)
    assert_not_nil assigns(:pagy)
    assert_not_nil assigns(:runs)
    assert_not_nil assigns(:table_data)
    assert_equal @job, assigns(:job)
  end

  test "index action orders runs by occurred_at desc" do
    get rails_pulse.job_runs_path(@job)

    assert_response :success
    runs = assigns(:runs)

    # Verify runs are ordered by occurred_at desc (most recent first)
    assert_operator runs.size, :>, 1
    runs.each_cons(2) do |current, next_run|
      assert_operator current.occurred_at, :>=, next_run.occurred_at
    end
  end

  test "index action with ransack search by status" do
    get rails_pulse.job_runs_path(@job), params: { q: { status_eq: "success" } }

    assert_response :success
    runs = assigns(:runs)

    # All returned runs should have status "success"
    assert runs.all? { |run| run.status == "success" }
  end

  test "index action with ransack search by adapter" do
    get rails_pulse.job_runs_path(@job), params: { q: { adapter_eq: "sidekiq" } }

    assert_response :success
    runs = assigns(:runs)

    # All returned runs should have adapter "sidekiq"
    assert runs.all? { |run| run.adapter == "sidekiq" }
  end

  test "index action respects pagination" do
    get rails_pulse.job_runs_path(@job), params: { limit: 10 }

    assert_response :success
    pagy = assigns(:pagy)
    runs = assigns(:runs)

    # Should have pagination set up correctly
    assert_not_nil pagy
    assert_operator runs.size, :<=, 10
  end

  # Show Action Tests
  test "show action loads successfully" do
    get rails_pulse.job_run_path(@job, @run)

    assert_response :success
    assert_not_nil assigns(:job)
    assert_not_nil assigns(:run)
    assert_not_nil assigns(:operations)
    assert_not_nil assigns(:operation_timeline)
    assert_not_nil assigns(:operations_by_type)
    assert_not_nil assigns(:sql_operations)
    assert_equal @job, assigns(:job)
    assert_equal @run, assigns(:run)
  end

  test "show action orders operations by start_time" do
    get rails_pulse.job_run_path(@job, @run)

    assert_response :success
    operations = assigns(:operations)

    # Operations should be ordered by start_time ascending if there are multiple
    if operations.size > 1
      operations.each_cons(2) do |current, next_op|
        assert_operator current.start_time, :<=, next_op.start_time
      end
    end
  end

  test "show action groups operations by type" do
    get rails_pulse.job_run_path(@job, @run)

    assert_response :success
    operations_by_type = assigns(:operations_by_type)

    # operations_by_type should be a hash grouping operations by their type
    assert_instance_of Hash, operations_by_type

    # Each group should only contain operations of that type
    operations_by_type.each do |type, ops|
      assert ops.all? { |op| op.operation_type == type }
    end
  end

  test "show action loads sql operations with includes" do
    get rails_pulse.job_run_path(@job, @run)

    assert_response :success
    sql_operations = assigns(:sql_operations)

    # SQL operations should be filtered to only sql type
    assert sql_operations.all? { |op| op.operation_type == "sql" }

    # Check that query associations are eager loaded (no N+1)
    assert_no_queries do
      sql_operations.each { |op| op.query&.normalized_sql }
    end
  end

  test "show action orders sql operations by duration desc" do
    get rails_pulse.job_run_path(@job, @run)

    assert_response :success
    sql_operations = assigns(:sql_operations)

    # SQL operations should be ordered by duration desc (slowest first)
    if sql_operations.size > 1
      sql_operations.each_cons(2) do |current, next_op|
        assert_operator current.duration.to_f, :>=, next_op.duration.to_f
      end
    end
  end

  test "show action creates operation timeline chart" do
    get rails_pulse.job_run_path(@job, @run)

    assert_response :success
    operation_timeline = assigns(:operation_timeline)

    assert_instance_of RailsPulse::Charts::OperationsChart, operation_timeline
  end

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end

  def assert_no_queries(&block)
    queries = []
    query_subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] unless payload[:name] == "SCHEMA"
    end

    block.call

    assert_equal 0, queries.size, "Expected no queries, but #{queries.size} were executed:\n#{queries.join("\n")}"
  ensure
    ActiveSupport::Notifications.unsubscribe(query_subscriber) if query_subscriber
  end
end
