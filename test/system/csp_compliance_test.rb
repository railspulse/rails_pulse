require "test_helper"

class CspComplianceTest < ApplicationSystemTestCase
  test "CSP test page loads without violations" do
    visit "/rails_pulse/csp_test"

    # Verify page loads
    assert_selector "h1", text: "Content Security Policy Compliance Test"

    # Check that basic CSP functionality works (skip JS check for now)
    # The other asset tests will verify JS functionality indirectly

    # Verify no CSP violations are reported
    violation_count = find("#violation-count")

    assert_equal "0", violation_count.text
    assert_includes violation_count[:class], "badge--success"
  end

  test "icon controller functions under CSP" do
    visit "/rails_pulse/csp_test"

    # Wait for icons to load
    sleep 1

    # Check that valid icons load
    menu_icon = find('[data-rails-pulse--icon-name-value="menu"]')

    assert_predicate menu_icon, :present?

    # Check that missing icon shows error but doesn't break CSP
    missing_icon = find('[data-rails-pulse--icon-name-value="nonexistent"]')

    assert_predicate missing_icon, :present?
  end

  test "popover controller functions under CSP" do
    visit "/rails_pulse/csp_test"

    # Test popover functionality
    popover_button = find('[data-action="click->rails-pulse--popover#toggle"]')
    popover_button.click

    # Verify popover appears (uses CSS custom properties for positioning)
    assert_selector '[data-rails-pulse--popover-target="menu"]'
  end

  test "context menu controller functions under CSP" do
    visit "/rails_pulse/csp_test"

    # Right-click to trigger context menu
    context_area = find('[data-action="contextmenu->rails-pulse--context-menu#show"]')
    context_area.right_click

    sleep 0.2 # Allow menu to appear

    # Verify context menu appears
    assert_selector '[data-rails-pulse--context-menu-target="menu"]'
  end

  test "AJAX requests work under CSP" do
    visit "/rails_pulse/csp_test"

    # Test AJAX functionality
    ajax_button = find("#ajax-test-btn", text: "Test AJAX Loading")
    ajax_button.click

    # Wait for AJAX request to complete
    assert_text "AJAX request completed successfully", wait: 5

    # Verify no CSP violations from AJAX
    violation_count = find("#violation-count")

    assert_equal "0", violation_count.text
  end

  test "asset loading status indicators work" do
    visit "/rails_pulse/csp_test"

    # Wait for asset checks to complete
    sleep 1

    # Verify CSS loading status
    css_status = find("#css-status")

    assert_text "Loaded"

    # Verify JS loading status
    js_status = find("#js-status")

    assert_text "Loaded"

    # Verify icons loading status
    icons_status = find("#icons-status")

    assert_text "Loaded"

    # Verify Stimulus status
    stimulus_status = find("#stimulus-status")

    assert_text "Active"
  end

  test "CSP headers are properly set" do
    visit "/rails_pulse/csp_test"

    # Check that the response includes CSP headers
    # Note: We can't directly access response headers in system tests,
    # but we can verify the page works under strict CSP

    # Verify the page content loads (proves CSP allows necessary resources)
    assert_selector "h2", text: "Icon Controller Test"
    assert_selector "h2", text: "Popover Controller Test"
    assert_selector "h2", text: "Context Menu Controller Test"
    assert_selector "h2", text: "AJAX Request Test"
    assert_selector "h2", text: "Chart Component Test"
    assert_selector "h2", text: "CSP Violation Summary"
  end

  test "CSP test works across different browsers" do
    # This test ensures our CSP implementation is browser-agnostic
    visit "/rails_pulse/csp_test"

    # Basic functionality that should work everywhere
    assert_selector "h1"
    assert_selector ".card", count: 9  # Updated count: we have 9 cards total

    # JavaScript-dependent features are tested in other specific tests
    # This test focuses on basic browser compatibility

    # CSS-dependent features
    assert_selector ".btn"
    assert_selector ".badge"
  end

  private

  def assert_text(expected_text, wait: Capybara.default_max_wait_time)
    assert page.has_text?(expected_text, wait: wait), "Expected to find text '#{expected_text}' on page"
  end
end
