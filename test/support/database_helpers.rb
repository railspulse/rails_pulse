require "fileutils"

module DatabaseHelpers
  # Configure database adapter based on environment
  def self.configure_test_database
    # For now, let's just use the existing test database connection
    # and avoid reconfiguring to prevent issues
    return unless ENV["FORCE_DB_CONFIG"] == "true"

    adapter = ENV.fetch("DB", "sqlite3")

    # Configure database connection
    configure_database_connection(adapter)

    # Run migrations to ensure tables exist
    ensure_test_tables_exist
  end

  def self.configure_database_connection(adapter)
    case adapter
    when "sqlite3"
      # Force file-based SQLite in CI to avoid connection isolation issues
      use_memory_database = ENV.fetch("MEMORY_DATABASE", "false") == "true" && ENV["CI"] != "true"
      if use_memory_database
        configure_memory_sqlite
      else
        configure_file_sqlite
      end
    when "mysql", "mysql2"
      configure_mysql
    when "postgresql"
      configure_postgresql
    end
  end

  def self.ensure_test_tables_exist
    # Use a mutex to prevent race conditions in parallel testing
    @table_creation_mutex ||= Mutex.new

    @table_creation_mutex.synchronize do
      begin
        # Check if all required tables exist
        required_tables = [ "rails_pulse_routes", "rails_pulse_requests", "rails_pulse_queries", "rails_pulse_operations", "rails_pulse_summaries" ]

        # Use the same connection that Rails Pulse models will use
        connection = defined?(RailsPulse::ApplicationRecord) ? RailsPulse::ApplicationRecord.connection : ActiveRecord::Base.connection

        if required_tables.all? { |table| connection.table_exists?(table) }
          return
        end

        # Create Rails Pulse tables for testing
        puts "Creating Rails Pulse test tables..." if ENV["CI"] == "true" || ENV["VERBOSE"] == "true"

        ActiveRecord::Migration.suppress_messages do
          create_rails_pulse_test_schema
        end

        # Verify tables were created successfully
        missing_tables = required_tables.reject { |table| connection.table_exists?(table) }
        if missing_tables.any?
          error_msg = "Rails Pulse test tables were not created: #{missing_tables.join(', ')}"
          puts error_msg
          raise "#{error_msg}. Database connection: #{connection.adapter_name}"
        end
      rescue => e
        # In CI, fail fast if table creation fails
        if ENV["CI"] == "true"
          puts "Table creation failed: #{e.class} - #{e.message}"
          puts "Database: #{ActiveRecord::Base.connection_db_config.database}"
          puts "Adapter: #{ActiveRecord::Base.connection.adapter_name}"
          raise e
        else
          puts "Warning: Table creation failed: #{e.class} - #{e.message}" if ENV["VERBOSE"] == "true"
          puts "Backtrace: #{e.backtrace.first(3).join("\n")}" if ENV["VERBOSE"] == "true"
        end
      end
    end
  end

  def self.create_rails_pulse_test_schema
    # Load the main Rails Pulse schema instead of duplicating table definitions
    schema_file = File.expand_path("../../../db/rails_pulse_schema.rb", __dir__)
    require schema_file

    # Call the schema lambda with the RailsPulse connection (falls back to ActiveRecord::Base if no separate connection)
    connection = defined?(RailsPulse::ApplicationRecord) ? RailsPulse::ApplicationRecord.connection : ActiveRecord::Base.connection
    RailsPulse::Schema.call(connection)
  end

  private

  def self.configure_memory_sqlite
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:",
      pool: 5,
      timeout: 5000
    )
  end

  def self.configure_file_sqlite
    # Ensure directory exists
    db_path = "test/dummy/storage/test.sqlite3"
    FileUtils.mkdir_p(File.dirname(db_path))

    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: db_path,
      pool: 5,
      timeout: 5000
    )
  end

  def self.configure_mysql
    # First ensure database exists
    create_mysql_database_if_needed

    # Retry connection establishment in case MySQL service is starting up
    retries = 3
    begin
      # Build connection config to force TCP connections
      config = {
        adapter: "mysql2",
        database: "rails_pulse_test",
        username: ENV.fetch("MYSQL_USERNAME", "root"),
        password: ENV.fetch("MYSQL_PASSWORD", ""),
        host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),  # Use 127.0.0.1 instead of localhost to force TCP
        port: ENV.fetch("MYSQL_PORT", 3306).to_i,
        # Add connection timeout for CI
        connect_timeout: 30,
        read_timeout: 30,
        write_timeout: 30
      }

      ActiveRecord::Base.establish_connection(config)

      # Test the connection
      ActiveRecord::Base.connection.execute("SELECT 1")

    rescue => e
      retries -= 1
      if retries > 0
        sleep 2
        retry
      else
        raise e
      end
    end
  end


  def self.create_mysql_database_if_needed
    # Connect to MySQL server (not specific database) to create the test database
    begin
      # Build admin connection config to force TCP connections
      admin_config = {
        host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),  # Use 127.0.0.1 instead of localhost to force TCP
        port: ENV.fetch("MYSQL_PORT", 3306).to_i,
        username: ENV.fetch("MYSQL_USERNAME", "root"),
        password: ENV.fetch("MYSQL_PASSWORD", ""),
        connect_timeout: 30
      }

      admin_connection = Mysql2::Client.new(admin_config)
      admin_connection.query("CREATE DATABASE IF NOT EXISTS rails_pulse_test")
      admin_connection.close
    rescue => e
      # Database creation failed, but this might be okay if it already exists
    end
  end

  def self.configure_postgresql
    ActiveRecord::Base.establish_connection(
      adapter: "postgresql",
      database: "rails_pulse_test",
      username: ENV.fetch("POSTGRES_USERNAME", "postgres"),
      password: ENV.fetch("POSTGRES_PASSWORD", ""),
      host: ENV.fetch("POSTGRES_HOST", "localhost"),
      port: ENV.fetch("POSTGRES_PORT", 5432)
    )
  end

  # Simple database setup/teardown
  def setup_test_database
    # Tables are already ensured to exist in the main setup
    # No custom transaction management needed - let Rails handle it
  end

  def teardown_test_database
    # Let DatabaseCleaner and Rails handle cleanup
    # No manual transaction management needed
  end

  def using_memory_database?
    config = ActiveRecord::Base.connection_db_config.adapter
    database = ActiveRecord::Base.connection_db_config.database
    database == ":memory:" || config == "sqlite3"
  end
end
