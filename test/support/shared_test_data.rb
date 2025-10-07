# Shared test data that can be used across multiple test files
# This provides a consistent set of test data using Rails engine fixtures
module SharedTestData
  def load_shared_test_data
    # Load fixture data into instance variables for backward compatibility
    load_fixture_routes
    load_fixture_queries
    load_fixture_requests
    load_fixture_operations
  end

  private

  def load_fixture_routes
    @api_users_route = rails_pulse_routes(:api_users)
    @api_posts_route = rails_pulse_routes(:api_posts)
    @api_test_route = rails_pulse_routes(:api_test)
    @api_other_route = rails_pulse_routes(:api_other)
    @api_cleanup_route = rails_pulse_routes(:api_other) # Reuse existing fixture, or create new one if needed
  end

  def load_fixture_queries
    @select_users_query = rails_pulse_queries(:simple_query)
    @select_posts_query = rails_pulse_queries(:complex_query)
    @select_test_query = rails_pulse_queries(:analyzed_query)
  end

  def load_fixture_requests
    @users_request_1 = rails_pulse_requests(:users_request_1)
    @users_request_2 = rails_pulse_requests(:users_request_2)
    @posts_request = rails_pulse_requests(:posts_request)
    @error_request = rails_pulse_requests(:error_request)
  end

  def load_fixture_operations
    @sql_operation_1 = rails_pulse_operations(:sql_operation_3) # This links to simple_query
    @controller_operation_1 = rails_pulse_operations(:controller_operation_1)
    @template_operation_1 = rails_pulse_operations(:template_operation_1)
    @sql_operation_2 = rails_pulse_operations(:sql_operation_2) # This links to complex_query
  end
end
