require "test_helper"
require "capybara/rails"
require "capybara/minitest"

# Explicitly require support modules
require_relative "database_helpers"
require_relative "factory_helpers"
require_relative "smoke_test_helpers"

# Chrome throws UnknownError (CDP -32000, "Node with given id does not belong to the
# document") when a DOM node is detached mid-query — e.g. Turbo navigating while Capybara
# is checking element visibility. Capybara only auto-retries on StaleElementReferenceError,
# so without this patch the suite crashes. Returning false from visible? causes Capybara to
# exclude the detached node and retry the full query within the wait: timeout.
module CapybaraDetachedNodeFix
  DETACHED_NODE_MSG = "Node with given id does not belong to the document"

  def visible?
    super
  rescue Selenium::WebDriver::Error::UnknownError => e
    raise unless e.message.include?(DETACHED_NODE_MSG)
    false
  end
end

Capybara::Selenium::ChromeNode.prepend(CapybaraDetachedNodeFix)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  Capybara.server = :puma, { Silent: true }

  driven_by :selenium, using: :chrome, screen_size: [ 1400, 1400 ] do |options|
    options.add_argument("--headless") unless ENV["BROWSER"] == "true"
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
  include SmokeTestHelpers

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
end
