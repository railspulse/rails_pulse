require "test_helper"
require "capybara/rails"
require "capybara/minitest"

# Explicitly require support modules
require_relative "database_helpers"
require_relative "factory_helpers"
require_relative "smoke_test_helpers"

# Chrome throws UnknownError (CDP -32000, "Node with given id does not belong to the
# document") when a DOM node is detached mid-query — e.g. a form submit replacing the page
# while Capybara is reading a dialog it already matched. Capybara only auto-retries on
# StaleElementReferenceError, so without this patch the suite crashes.
#
# visible? returning false excludes the detached node from selector results.
# visible_text/all_text returning "" lets assert_no_selector finish building its
# ExpectationNotMet message (which maps .text over matches) so synchronize can retry.
module CapybaraDetachedNodeFix
  DETACHED_NODE_MSG = "Node with given id does not belong to the document"

  def visible?
    super
  rescue Selenium::WebDriver::Error::UnknownError => e
    raise unless detached_node_error?(e)
    false
  end

  def visible_text
    super
  rescue Selenium::WebDriver::Error::UnknownError => e
    raise unless detached_node_error?(e)
    ""
  end

  def all_text
    super
  rescue Selenium::WebDriver::Error::UnknownError => e
    raise unless detached_node_error?(e)
    ""
  end

  private

  def detached_node_error?(error)
    error.message.include?(DETACHED_NODE_MSG)
  end
end

Capybara::Selenium::ChromeNode.prepend(CapybaraDetachedNodeFix)

# Mocha 2.7.1 bug: ActionDispatch::SystemTestCase's after_teardown fires mocha_teardown
# even when mocha_setup never ran. Mockery.teardown calls @instances.pop but @instances
# is nil when setup was skipped, crashing with NoMethodError. Guard the class-level teardown.
if defined?(Mocha::Mockery)
  module MochaNilSafeTeardown
    def teardown(origin = nil)
      return unless @instances&.any?
      super
    end
  end
  Mocha::Mockery.singleton_class.prepend(MochaNilSafeTeardown)
end

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
