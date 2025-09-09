# Configure Rails Environment
ENV["RAILS_ENV"] = "test"
# Disable parallel testing completely
ENV["PARALLEL_WORKERS"] = "0"

# Load environment variables from .env file
begin
  require "dotenv"
  Dotenv.load(File.expand_path("../.env", __dir__))
rescue LoadError
  # dotenv not available, skip
end

require_relative "../test/dummy/config/environment"

# Configure database early if needed
if ENV["FORCE_DB_CONFIG"] == "true"
  require_relative "support/database_helpers"
  DatabaseHelpers.configure_test_database
end
# Only use dummy app migrations to avoid conflicts
ActiveRecord::Migrator.migrations_paths = [
  File.expand_path("../test/dummy/db/migrate", __dir__)
]

# Override pending migration check
class ActiveRecord::Migration
  def self.check_pending_migrations
    # Skip for testing
  end
end

require "rails/test_help"

# Load rails-controller-testing for assigns()
begin
  require "rails-controller-testing"
rescue LoadError
  puts "Warning: rails-controller-testing not available for testing"
end

# Load test dependencies
require "mocha/minitest"
require "timecop"
require "factory_bot_rails"
require "shoulda-matchers"
require "minitest/reporters"
require "database_cleaner/active_record"

# Use progress reporter for cleaner output
Minitest::Reporters.use! Minitest::Reporters::ProgressReporter.new

# Load support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

# Configure fast testing
class ActiveSupport::TestCase
  # Disable parallel testing to avoid race conditions with table creation
  parallelize(workers: 1) if respond_to?(:parallelize)

  # Include test helpers
  include DatabaseHelpers
  include PerformanceHelpers
  include ModelTestHelpers
  include ControllerTestHelpers
  include FactoryHelpers

  # Configure FactoryBot
  if defined?(FactoryBot)
    include FactoryBot::Syntax::Methods
    FactoryBot.definition_file_paths = [ File.expand_path("factories", __dir__) ]
    FactoryBot.find_definitions
  end

  # Configure shoulda-matchers
  if defined?(Shoulda::Matchers)
    Shoulda::Matchers.configure do |config|
      config.integrate do |with|
        with.test_framework :minitest
        with.library :rails
      end
    end

    # Include Shoulda Matchers in test classes
    include Shoulda::Matchers::ActiveModel
    include Shoulda::Matchers::ActiveRecord
  end

  # Configure database_cleaner
  if defined?(DatabaseCleaner)
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
  end


  # Fast setup/teardown using transactions
  setup do
    # Ensure Rails Pulse tables exist for this test
    DatabaseHelpers.ensure_test_tables_exist

    setup_test_database if respond_to?(:setup_test_database)

    # Stub time operations only
    stub_time_operations
  end

  teardown do
    teardown_test_database if respond_to?(:teardown_test_database)

    # Clean database if using database_cleaner
    if defined?(DatabaseCleaner)
      DatabaseCleaner.clean
    end

    # Reset stubs if available
    if defined?(Mocha)
      Mocha::Mockery.instance.teardown
    end

    if defined?(Timecop)
      Timecop.return
    end
  end
end


# Database switching based on environment variables (must happen after Rails initialization)
if ENV["FORCE_DB_CONFIG"] == "true"
  DatabaseHelpers.configure_test_database
else
  # Ensure we use the Rails database configuration (important for CI)
  unless ActiveRecord::Base.connected?
    ActiveRecord::Base.establish_connection(Rails.application.config.database_configuration["test"])
  end
end

# Always ensure Rails Pulse tables exist BEFORE any tests run
DatabaseHelpers.ensure_test_tables_exist


# Display test environment information
if ENV["VERBOSE"] == "true"
  puts "\n" + "=" * 50
  puts "🚀 Rails Pulse Test Suite"
  puts "=" * 50
  puts "Rails version: #{Rails.version}"
  puts "Database: #{ENV['DB'] || 'sqlite3'}"
  puts "=" * 50
  puts
end

# Load fixtures from the engine (temporarily disabled to avoid foreign key issues)
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  # ActiveSupport::TestCase.fixtures :all  # Disabled due to foreign key violations
end

# Integration test specific configuration
class ActionDispatch::IntegrationTest
  # Use file-based database for integration tests (unless overridden by CI)
  def setup
    # Only set MEMORY_DATABASE=false if it's not already set by CI
    ENV["MEMORY_DATABASE"] ||= "false"
    DatabaseHelpers.configure_test_database
    super
  end
end

# System test specific configuration
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Include validation helpers for all system tests
  include ChartValidationHelpers if defined?(ChartValidationHelpers)
  include TableValidationHelpers if defined?(TableValidationHelpers)
end
