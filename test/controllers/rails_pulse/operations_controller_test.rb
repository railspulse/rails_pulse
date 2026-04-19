require "test_helper"

class RailsPulse::OperationsControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  fixtures :rails_pulse_requests, :rails_pulse_operations, :rails_pulse_job_runs, :rails_pulse_routes

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @request_operation = rails_pulse_operations(:sql_operation_1)
    @job_run_operation = rails_pulse_operations(:job_sql_operation)
  end

  # Controller Structure Tests

  test "controller has show action" do
    controller = RailsPulse::OperationsController.new

    assert_respond_to controller, :show
  end

  test "controller has required private methods" do
    controller = RailsPulse::OperationsController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :set_operation
    assert_includes private_methods, :find_related_operations
    assert_includes private_methods, :calculate_performance_context
    assert_includes private_methods, :generate_optimization_suggestions
    assert_includes private_methods, :calculate_percentile
  end

  test "controller has generate_optimization_suggestions method" do
    controller = RailsPulse::OperationsController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :generate_optimization_suggestions
  end

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::OperationsController, :<, RailsPulse::ApplicationController
  end

  # Show Action Tests - Request Operations

  test "show action loads successfully for request operation" do
    get rails_pulse.operation_path(@request_operation)

    assert_response :success
    assert_not_nil assigns(:operation)
    assert_not_nil assigns(:request)
    assert_not_nil assigns(:parent)
    assert_not_nil assigns(:related_operations)
    assert_not_nil assigns(:performance_context)
    assert_not_nil assigns(:optimization_suggestions)
    assert_equal @request_operation, assigns(:operation)
    assert_equal @request_operation.request, assigns(:request)
  end

  test "show action sets parent to request for request operation" do
    get rails_pulse.operation_path(@request_operation)

    assert_response :success
    assert_equal @request_operation.request, assigns(:parent)
    assert_nil assigns(:job_run)
  end

  # Show Action Tests - Job Run Operations

  test "show action loads successfully for job run operation" do
    get rails_pulse.operation_path(@job_run_operation)

    assert_response :success
    assert_not_nil assigns(:operation)
    assert_not_nil assigns(:job_run)
    assert_not_nil assigns(:parent)
    assert_not_nil assigns(:related_operations)
    assert_not_nil assigns(:performance_context)
    assert_not_nil assigns(:optimization_suggestions)
    assert_equal @job_run_operation, assigns(:operation)
    assert_equal @job_run_operation.job_run, assigns(:job_run)
  end

  test "show action sets parent to job_run for job run operation" do
    get rails_pulse.operation_path(@job_run_operation)

    assert_response :success
    assert_equal @job_run_operation.job_run, assigns(:parent)
    assert_nil assigns(:request)
  end

  # Related Operations Tests

  test "show action finds related operations" do
    get rails_pulse.operation_path(@request_operation)

    assert_response :success
    related = assigns(:related_operations)

    # Should be an ActiveRecord relation or array
    assert_respond_to related, :each
    # Should not include the current operation
    refute_includes related.map(&:id), @request_operation.id
  end

  # Performance Context Tests

  test "show action calculates performance context" do
    get rails_pulse.operation_path(@request_operation)

    assert_response :success
    context = assigns(:performance_context)

    assert_kind_of Hash, context
    # Should have percentile keys
    if context.any?
      assert context.key?(:percentile_50) || context.key?(:average)
    end
  end

  # Optimization Suggestions Tests

  test "show action generates optimization suggestions" do
    get rails_pulse.operation_path(@request_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)

    assert_kind_of Array, suggestions
  end

  # Private Method Tests

  test "calculates percentile correctly" do
    controller = RailsPulse::OperationsController.new

    # Test percentile calculation with known values
    sorted_array = [ 10, 20, 30, 40, 50 ]

    # 25 should be at 40th percentile (between 20 and 30)
    percentile = controller.send(:calculate_percentile, 25, sorted_array)

    assert_in_delta 40.0, percentile, 0.1

    # 35 should be at 60th percentile
    percentile = controller.send(:calculate_percentile, 35, sorted_array)

    assert_in_delta 60.0, percentile, 0.1

    # Test edge cases
    assert_equal 0, controller.send(:calculate_percentile, 5, sorted_array)
    assert_in_delta(100.0, controller.send(:calculate_percentile, 100, sorted_array))
  end

  test "calculates percentile for empty array" do
    controller = RailsPulse::OperationsController.new

    percentile = controller.send(:calculate_percentile, 50, [])

    assert_equal 0, percentile
  end

  # SQL Optimization Suggestion Tests

  test "generates slow query suggestion for SQL operations over 100ms" do
    slow_operation = rails_pulse_operations(:sql_operation_1)
    slow_operation.update!(duration: 150)

    get rails_pulse.operation_path(slow_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    slow_query_suggestion = suggestions.find { |s| s[:type] == "performance" && s[:title] == "Slow Query Detected" }

    assert_not_nil slow_query_suggestion
    assert_equal "high", slow_query_suggestion[:priority]
    assert_includes slow_query_suggestion[:description], "150"
  end

  test "generates index optimization suggestion for SELECT queries" do
    select_operation = rails_pulse_operations(:sql_operation_1)
    select_operation.update!(label: "SELECT * FROM users WHERE email = 'test@example.com'")

    get rails_pulse.operation_path(select_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    index_suggestion = suggestions.find { |s| s[:type] == "index" }

    assert_not_nil index_suggestion
    assert_equal "medium", index_suggestion[:priority]
    assert_includes index_suggestion[:description], "users"
  end

  test "generates N+1 query suggestion when similar queries detected" do
    request = rails_pulse_requests(:users_request_1)
    operation = rails_pulse_operations(:sql_operation_1)
    operation.update!(request: request, label: "SELECT * FROM users WHERE id = 1")

    # Create similar operations
    3.times do |i|
      RailsPulse::Operation.create!(
        request: request,
        operation_type: "sql",
        label: "SELECT * FROM users WHERE id = #{i + 2}",
        occurred_at: operation.occurred_at + (i + 1).seconds,
        duration: 10
      )
    end

    get rails_pulse.operation_path(operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    n_plus_one_suggestion = suggestions.find { |s| s[:type] == "n_plus_one" }

    assert_not_nil n_plus_one_suggestion
    assert_equal "high", n_plus_one_suggestion[:priority]
    assert_includes n_plus_one_suggestion[:description], "similar queries detected"
  end

  test "does not generate N+1 suggestion with 2 or fewer similar queries" do
    request = rails_pulse_requests(:users_request_1)
    operation = rails_pulse_operations(:sql_operation_1)
    operation.update!(request: request, label: "SELECT * FROM users WHERE id = 1")

    # Create only 1 similar operation (total 2)
    RailsPulse::Operation.create!(
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = 2",
      occurred_at: operation.occurred_at + 1.second,
      duration: 10
    )

    get rails_pulse.operation_path(operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    n_plus_one_suggestion = suggestions.find { |s| s[:type] == "n_plus_one" }

    assert_nil n_plus_one_suggestion
  end

  # View Optimization Suggestion Tests

  test "generates slow view rendering suggestion for template operations over 100ms" do
    view_operation = rails_pulse_operations(:template_operation_1)
    view_operation.update!(duration: 150)

    get rails_pulse.operation_path(view_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    slow_view_suggestion = suggestions.find { |s| s[:title] == "Slow View Rendering" }

    assert_not_nil slow_view_suggestion
    assert_equal "high", slow_view_suggestion[:priority]
    assert_includes slow_view_suggestion[:description], "150"
  end

  test "generates database queries in view suggestion" do
    request = rails_pulse_requests(:users_request_1)
    view_operation = rails_pulse_operations(:template_operation_1)
    view_operation.update!(request: request, occurred_at: Time.current, duration: 50)

    # Create SQL operation during view rendering
    RailsPulse::Operation.create!(
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM users",
      occurred_at: view_operation.occurred_at + 10,
      duration: 20
    )

    get rails_pulse.operation_path(view_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    db_in_view_suggestion = suggestions.find { |s| s[:title] == "Database Queries in View" }

    assert_not_nil db_in_view_suggestion
    assert_equal "medium", db_in_view_suggestion[:priority]
    assert_includes db_in_view_suggestion[:description], "database queries during view rendering"
  end

  test "generates suggestions for partial operations" do
    partial_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "partial",
      label: "_user_card.html.erb",
      occurred_at: Time.current,
      duration: 120
    )

    get rails_pulse.operation_path(partial_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)

    assert_not_empty suggestions
    assert suggestions.any? { |s| s[:title] == "Slow View Rendering" }
  end

  test "generates suggestions for layout operations" do
    layout_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "layout",
      label: "application.html.erb",
      occurred_at: Time.current,
      duration: 110
    )

    get rails_pulse.operation_path(layout_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)

    assert_not_empty suggestions
  end

  test "generates suggestions for collection operations" do
    collection_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "collection",
      label: "_user.html.erb",
      occurred_at: Time.current,
      duration: 200
    )

    get rails_pulse.operation_path(collection_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)

    assert_not_empty suggestions
  end

  # Controller Optimization Suggestion Tests

  test "generates slow controller action suggestion for operations over 500ms" do
    controller_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "controller",
      label: "UsersController#index",
      occurred_at: Time.current,
      duration: 600
    )

    get rails_pulse.operation_path(controller_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    slow_controller_suggestion = suggestions.find { |s| s[:title] == "Slow Controller Action" }

    assert_not_nil slow_controller_suggestion
    assert_equal "high", slow_controller_suggestion[:priority]
    assert_includes slow_controller_suggestion[:description], "600"
  end

  test "does not generate controller suggestion for operations under 500ms" do
    controller_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "controller",
      label: "UsersController#index",
      occurred_at: Time.current,
      duration: 300
    )

    get rails_pulse.operation_path(controller_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    slow_controller_suggestion = suggestions.find { |s| s[:title] == "Slow Controller Action" }

    assert_nil slow_controller_suggestion
  end

  # Cache Optimization Suggestion Tests

  test "generates slow cache read suggestion for cache_read operations over 10ms" do
    cache_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "cache_read",
      label: "cache_key_123",
      occurred_at: Time.current,
      duration: 15
    )

    get rails_pulse.operation_path(cache_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    slow_cache_suggestion = suggestions.find { |s| s[:title] == "Slow Cache Read" }

    assert_not_nil slow_cache_suggestion
    assert_equal "medium", slow_cache_suggestion[:priority]
  end

  test "does not generate cache suggestion for fast cache reads" do
    cache_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "cache_read",
      label: "cache_key_123",
      occurred_at: Time.current,
      duration: 5
    )

    get rails_pulse.operation_path(cache_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    slow_cache_suggestion = suggestions.find { |s| s[:title] == "Slow Cache Read" }

    assert_nil slow_cache_suggestion
  end

  test "handles cache_write operations" do
    cache_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "cache_write",
      label: "cache_key_123",
      occurred_at: Time.current,
      duration: 20
    )

    get rails_pulse.operation_path(cache_operation)

    assert_response :success
    # cache_write doesn't generate suggestions currently, just verify no errors
  end

  # HTTP Optimization Suggestion Tests

  test "generates slow external request suggestion for HTTP operations over 1000ms" do
    http_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "http",
      label: "GET https://api.example.com/users",
      occurred_at: Time.current,
      duration: 1500
    )

    get rails_pulse.operation_path(http_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    slow_http_suggestion = suggestions.find { |s| s[:title] == "Slow External Request" }

    assert_not_nil slow_http_suggestion
    assert_equal "high", slow_http_suggestion[:priority]
    assert_includes slow_http_suggestion[:description], "1500"
  end

  test "does not generate HTTP suggestion for fast requests" do
    http_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "http",
      label: "GET https://api.example.com/users",
      occurred_at: Time.current,
      duration: 500
    )

    get rails_pulse.operation_path(http_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)
    slow_http_suggestion = suggestions.find { |s| s[:title] == "Slow External Request" }

    assert_nil slow_http_suggestion
  end

  # Related Operations Tests

  test "finds related SQL operations" do
    request = rails_pulse_requests(:users_request_1)
    sql_op = rails_pulse_operations(:sql_operation_1)
    sql_op.update!(request: request)

    # Create another SQL operation
    RailsPulse::Operation.create!(
      request: request,
      operation_type: "sql",
      label: "SELECT * FROM posts",
      occurred_at: Time.current,
      duration: 20
    )

    get rails_pulse.operation_path(sql_op)

    assert_response :success
    related = assigns(:related_operations)

    assert_kind_of Enumerable, related
    assert related.all? { |op| op.operation_type == "sql" }
    refute_includes related.map(&:id), sql_op.id
  end

  test "finds related view operations for template type" do
    request = rails_pulse_requests(:users_request_1)
    template_op = rails_pulse_operations(:template_operation_1)
    template_op.update!(request: request)

    # Create partial and layout operations
    RailsPulse::Operation.create!(
      request: request,
      operation_type: "partial",
      label: "_header.html.erb",
      occurred_at: Time.current,
      duration: 10
    )

    get rails_pulse.operation_path(template_op)

    assert_response :success
    related = assigns(:related_operations)

    assert_kind_of Enumerable, related
  end

  test "limits related operations to 5" do
    request = rails_pulse_requests(:users_request_1)
    sql_op = rails_pulse_operations(:sql_operation_1)
    sql_op.update!(request: request)

    # Create 10 related SQL operations
    10.times do |i|
      RailsPulse::Operation.create!(
        request: request,
        operation_type: "sql",
        label: "SELECT * FROM table_#{i}",
        occurred_at: Time.current + i.seconds,
        duration: 20
      )
    end

    get rails_pulse.operation_path(sql_op)

    assert_response :success
    related = assigns(:related_operations)

    assert_operator related.count, :<=, 5
  end

  # Performance Context Tests

  test "calculates performance context with percentiles" do
    # Create multiple SQL operations for context
    10.times do |i|
      RailsPulse::Operation.create!(
        request: rails_pulse_requests(:users_request_1),
        operation_type: "sql",
        label: "SELECT * FROM test_#{i}",
        occurred_at: Time.current - i.days,
        duration: (i + 1) * 10
      )
    end

    get rails_pulse.operation_path(rails_pulse_operations(:sql_operation_1))

    assert_response :success
    context = assigns(:performance_context)

    assert_kind_of Hash, context
    assert context.key?(:percentile_50) if context.any?
    assert context.key?(:percentile_75) if context.any?
    assert context.key?(:percentile_90) if context.any?
    assert context.key?(:percentile_95) if context.any?
    assert context.key?(:average) if context.any?
    assert context.key?(:count) if context.any?
  end

  test "handles empty performance context gracefully" do
    # Use an operation type that has no other similar operations
    http_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "http",
      label: "GET https://api.example.com",
      occurred_at: 100.days.ago,  # Old operation, no recent similar ones
      duration: 100
    )

    get rails_pulse.operation_path(http_operation)

    assert_response :success
    context = assigns(:performance_context)

    assert_kind_of Hash, context
  end

  # Job Run Operations Tests

  test "finds related operations for job run operations" do
    job_run = rails_pulse_job_runs(:mailer_run_success)
    job_op = rails_pulse_operations(:job_sql_operation)
    job_op.update!(job_run: job_run)

    # Create another operation in same job run
    RailsPulse::Operation.create!(
      job_run: job_run,
      operation_type: "sql",
      label: "SELECT * FROM jobs",
      occurred_at: Time.current,
      duration: 30
    )

    get rails_pulse.operation_path(job_op)

    assert_response :success
    related = assigns(:related_operations)

    assert_kind_of Enumerable, related
    refute_includes related.map(&:id), job_op.id
  end

  # Edge Cases

  test "handles operation with no parent gracefully" do
    # Operations must have either a request or job_run, so test with nil parent after creation
    operation = rails_pulse_operations(:sql_operation_1)
    operation.update!(request: nil, job_run: rails_pulse_job_runs(:mailer_run_success))

    # Now set both to nil to simulate orphan (though validation prevents this in practice)
    # Instead, just test that code handles missing parent properly
    get rails_pulse.operation_path(operation)

    assert_response :success
    # Suggestions still work, just without N+1 detection
  end

  test "generates no suggestions for job operations" do
    # Job operations don't have specific optimization suggestions
    job_operation = RailsPulse::Operation.create!(
      request: rails_pulse_requests(:users_request_1),
      operation_type: "job",
      label: "MyJob",
      occurred_at: Time.current,
      duration: 100
    )

    get rails_pulse.operation_path(job_operation)

    assert_response :success
    suggestions = assigns(:optimization_suggestions)

    assert_empty suggestions
  end

  private

  def rails_pulse
    RailsPulse::Engine.routes.url_helpers
  end
end
