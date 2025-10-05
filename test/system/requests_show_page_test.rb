require "test_helper"

class RequestsShowPageTest < ApplicationSystemTestCase
  include SharedTestData

  def setup
    super
    load_shared_test_data
  end

  def test_request_show_page_loads_and_displays_operations
    visit_rails_pulse_path "/requests/#{@users_request_1.id}"

    # Should show request details
    assert_text @users_request_1.route.path_and_method
    assert_text "#{@users_request_1.duration.round(2)} ms"

    # Should show operations table when operations exist
    assert_selector "table.operations-table"
    assert_selector "table tbody tr", minimum: 1
  end

  def test_empty_state_displays_when_no_operations_exist
    # Create a request without operations using direct record creation
    route_without_ops = RailsPulse::Route.create!(path: "/test/no-ops", method: "GET")
    request_without_operations = RailsPulse::Request.create!(
      route: route_without_ops,
      duration: 100,
      status: 200,
      is_error: false,
      request_uuid: "test-no-ops",
      controller_action: "TestController#no_ops",
      occurred_at: 1.hour.ago
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
end
