require "test_helper"
require "capybara/rails"
require "capybara/minitest"

# Explicitly require support modules
require_relative "database_helpers"
require_relative "factory_helpers"
require_relative "config_test_helpers"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :chrome, screen_size: [ 1400, 1400 ] do |options|
    options.add_argument("--headless") unless ENV["BROWSER"]
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-gpu")
    options.add_argument("--disable-web-security")
    options.add_argument("--disable-features=VizDisplayCompositor")
    options.add_argument("--ignore-certificate-errors")
    options.add_argument("--disable-extensions")
  end

  # Include test helpers
  include DatabaseHelpers
  include FactoryHelpers
  include ConfigTestHelpers

  def setup
    setup_test_database
    super
  end

  def teardown
    super
    teardown_test_database if respond_to?(:teardown_test_database)
  end

  # Override to handle background errors
  def run(*)
    result = super
    # Clear any background JavaScript errors that don't affect the main test
    if page.driver.respond_to?(:browser) && page.driver.browser.respond_to?(:logs)
      begin
        page.driver.browser.logs.get(:browser)
      rescue
        # Ignore any log access errors
      end
    end
    result
  end

  private

  # Helper to visit RailsPulse routes
  def visit_rails_pulse_path(path)
    visit "/rails_pulse#{path}"
  end

  # Helper to wait for charts to load
  def wait_for_charts_to_load
    assert_selector "[data-chart]", wait: 10
  end

  # Helper to wait for tables to load
  def wait_for_tables_to_load
    assert_selector "table", wait: 10
  end
end
