# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

# Load environment variables from .env file
begin
  require "dotenv"
  Dotenv.load(File.expand_path("../.env", __dir__))
rescue LoadError
  # dotenv not available, skip
end

require_relative "../test/dummy/config/environment"

# Force database configuration early for MySQL in CI
if ENV["DATABASE_ADAPTER"] == "mysql2" || ENV["DATABASE_ADAPTER"] == "mysql"
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

# Load test dependencies
begin
  require "mocha/minitest"
rescue LoadError
  puts "Warning: mocha not available for testing"
end

begin
  require "timecop"
rescue LoadError
  puts "Warning: timecop not available for testing"
end

begin
  require "factory_bot_rails"
rescue LoadError
  puts "Warning: factory_bot_rails not available for testing"
end

begin
  require "shoulda-matchers"
rescue LoadError
  puts "Warning: shoulda-matchers not available for testing"
end

begin
  require "minitest/reporters"
  Minitest::Reporters.use! Minitest::Reporters::ProgressReporter.new
rescue LoadError
  puts "Warning: minitest-reporters not available for testing"
end

begin
  require "database_cleaner/active_record"
rescue LoadError
  puts "Warning: database_cleaner not available for testing"
end

# Load support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

# Configure fast testing
class ActiveSupport::TestCase
  # Enable parallel testing for speed (Rails 8.0+ only, but not for MySQL)
  if Rails.version.to_f >= 8.0 && ENV["DATABASE_ADAPTER"] != "mysql2"
    parallelize(workers: :number_of_processors)
  end

  # Disable transactional tests for MySQL to avoid savepoint issues
  self.use_transactional_tests = false if ENV["DATABASE_ADAPTER"] == "mysql2"

  # Disable transactional tests for MySQL to avoid savepoint issues
  self.use_transactional_tests = false if ENV["DATABASE_ADAPTER"] == "mysql2"

  # Include test helpers
  include DatabaseHelpers
  include PerformanceHelpers
  include StubHelpers
  include ModelTestHelpers
  include ControllerTestHelpers
  include FactoryHelpers
  include PerformanceTestHelpers
  include ConfigTestHelpers

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
  end

  # Configure database_cleaner - will be configured after database connection
  if defined?(DatabaseCleaner)
    DatabaseCleaner.strategy = :transaction  # Default, will be changed for MySQL
    DatabaseCleaner.start
  end

  # Configure database for speed
  def self.configure_database_for_test_type
    test_type = ENV.fetch("TEST_TYPE", "unit")

    case test_type
    when "unit", "functional"
      # Use memory database for unit/functional tests (fastest)
      ENV["MEMORY_DATABASE"] = "true"
    when "integration", "system"
      # Use file database for integration tests (more realistic)
      ENV["MEMORY_DATABASE"] = "false"
    end

    DatabaseHelpers.configure_test_database
  end

  # Fast setup/teardown using transactions
  setup do
    setup_test_database if respond_to?(:setup_test_database)

    # Stub expensive operations by default
    stub_rails_pulse_configuration
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

# Configure database based on test type
ActiveSupport::TestCase.configure_database_for_test_type

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

# Force table creation immediately in CI to avoid timing issues
if ENV["CI"] == "true"
  puts "Forcing table verification in CI..."
  required_tables = [ "rails_pulse_routes", "rails_pulse_requests", "rails_pulse_queries", "rails_pulse_operations" ]
  missing_tables = required_tables.reject { |table| ActiveRecord::Base.connection.table_exists?(table) }
  if missing_tables.any?
    puts "FATAL: Required tables missing after creation: #{missing_tables.join(', ')}"
    exit 1
  end
  puts "All required tables confirmed present."
end

# Display test environment information
puts "\n" + "=" * 80
puts "🚀 Rails Pulse Test Suite"
puts "=" * 80
puts "Ruby version:       #{RUBY_VERSION}"
puts "Rails version:      #{Rails.version}"
requested_adapter = ENV["DATABASE_ADAPTER"] || "sqlite3"
display_adapter = requested_adapter == "sqlite3" && ENV["FORCE_DB_CONFIG"] != "true" ? "sqlite3 (default)" : requested_adapter
actual_adapter = ActiveRecord::Base.connection.adapter_name
puts "DATABASE_ADAPTER:   #{display_adapter}"
puts "Actual adapter:     #{actual_adapter}"
if ENV["FORCE_DB_CONFIG"] != "true" && requested_adapter != "sqlite3"
  puts "📝 Note: Database switching disabled by default. Set FORCE_DB_CONFIG=true to enable."
end
puts "Database name:      #{ActiveRecord::Base.connection_db_config.database}"
puts "Test environment:   #{Rails.env}"
puts "=" * 80
puts

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
