# Shared test data that can be used across multiple test files
# This provides a consistent set of test data without the complexity of Rails engine fixtures
module SharedTestData
  def load_shared_test_data
    # Skip if data already exists to avoid duplication
    return if RailsPulse::Route.exists?

    create_test_routes
    create_test_queries
    create_test_requests
    create_test_operations
  end

  private

  def create_test_routes
    @api_users_route = RailsPulse::Route.create!(method: "GET", path: "/api/users")
    @api_posts_route = RailsPulse::Route.create!(method: "POST", path: "/api/posts")
    @api_test_route = RailsPulse::Route.create!(method: "GET", path: "/api/test")
    @api_other_route = RailsPulse::Route.create!(method: "POST", path: "/api/other")
    @api_cleanup_route = RailsPulse::Route.create!(method: "DELETE", path: "/api/cleanup")
  end

  def create_test_queries
    @select_users_query = RailsPulse::Query.create!(normalized_sql: "SELECT * FROM users WHERE id = ?")
    @select_posts_query = RailsPulse::Query.create!(normalized_sql: "SELECT * FROM posts WHERE id = ?")
    @select_test_query = RailsPulse::Query.create!(normalized_sql: "SELECT * FROM test WHERE id = ?")
  end

  def create_test_requests
    @users_request_1 = RailsPulse::Request.create!(
      route: @api_users_route,
      duration: 150.5,
      status: 200,
      is_error: false,
      request_uuid: "test-uuid-1",
      controller_action: "UsersController#index",
      occurred_at: 1.hour.ago
    )

    @users_request_2 = RailsPulse::Request.create!(
      route: @api_users_route,
      duration: 250.0,
      status: 200,
      is_error: false,
      request_uuid: "test-uuid-2",
      controller_action: "UsersController#show",
      occurred_at: 2.hours.ago
    )

    @posts_request = RailsPulse::Request.create!(
      route: @api_posts_route,
      duration: 180.0,
      status: 201,
      is_error: false,
      request_uuid: "test-uuid-3",
      controller_action: "PostsController#create",
      occurred_at: 1.hour.ago
    )

    @error_request = RailsPulse::Request.create!(
      route: @api_other_route,
      duration: 300.0,
      status: 500,
      is_error: true,
      request_uuid: "test-uuid-4",
      controller_action: "OtherController#action",
      occurred_at: 3.hours.ago
    )
  end

  def create_test_operations
    @sql_operation_1 = RailsPulse::Operation.create!(
      request: @users_request_1,
      query: @select_users_query,
      operation_type: "sql",
      label: "SELECT * FROM users WHERE id = ?",
      duration: 45.0,
      codebase_location: "app/models/user.rb:25",
      start_time: 10.0,
      occurred_at: 1.hour.ago
    )

    @controller_operation_1 = RailsPulse::Operation.create!(
      request: @users_request_1,
      operation_type: "controller",
      label: "UsersController#index",
      duration: 25.0,
      start_time: 5.0,
      occurred_at: 1.hour.ago
    )

    @template_operation_1 = RailsPulse::Operation.create!(
      request: @users_request_2,
      operation_type: "template",
      label: "render users/index.html.erb",
      duration: 25.0,
      start_time: 75.0,
      occurred_at: 2.hours.ago
    )

    @sql_operation_2 = RailsPulse::Operation.create!(
      request: @posts_request,
      query: @select_posts_query,
      operation_type: "sql",
      label: "SELECT * FROM posts WHERE id = ?",
      duration: 35.0,
      codebase_location: "app/models/post.rb:15",
      start_time: 8.0,
      occurred_at: 1.hour.ago
    )
  end
end
