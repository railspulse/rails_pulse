require "test_helper"

class RequestsShowPageTest < ApplicationSystemTestCase
  def setup
    super
    create_test_data
  end

  def test_request_show_page_loads_and_displays_operations
    visit_rails_pulse_path "/requests/#{@request.id}"

    # Should show request details
    assert_text @request.route.path_and_method
    assert_text @request.request_uuid
    assert_text "#{@request.duration.round(2)} ms"

    # Should show operations table when operations exist
    assert_selector "table.operations-table"
    assert_selector "table tbody tr", minimum: 1
  end

  def test_empty_state_displays_when_no_operations_exist
    # Create a request without operations
    request_without_operations = create(:request, 
      route: create(:route, path: "/test/no-ops", method: "GET"),
      duration: 100
    )

    visit_rails_pulse_path "/requests/#{request_without_operations.id}"

    # Should show request details
    assert_text request_without_operations.route.path_and_method

    # Should show empty state for operations
    assert_text "No operations found for this request."
    assert_text "This request may not have had any tracked operations."
    
    # Check for the search.svg image in the empty state
    assert_selector "img[src*='search.svg']"
    
    # Should not show operations table
    assert_no_selector "table.operations-table"
  end

  private

  def create_test_data
    @route = create(:route, path: "/api/test", method: "GET")
    @request = create(:request, route: @route, duration: 250)
    
    # Create some operations for the request
    create(:operation, 
      request: @request, 
      operation_type: "sql", 
      duration: 50, 
      label: "SELECT * FROM users",
      occurred_at: @request.occurred_at
    )
    create(:operation, 
      request: @request, 
      operation_type: "template", 
      duration: 100, 
      label: "Render users/index",
      occurred_at: @request.occurred_at + 0.05
    )
  end
end