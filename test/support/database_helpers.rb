require "fileutils"

module DatabaseHelpers
  # Configure database adapter based on environment
  def self.configure_test_database
    # For now, let's just use the existing test database connection
    # and avoid reconfiguring to prevent issues
    return unless ENV["FORCE_DB_CONFIG"] == "true"

    adapter = ENV.fetch("DATABASE_ADAPTER", "sqlite3")

    # Configure database connection
    configure_database_connection(adapter)

    # Run migrations to ensure tables exist
    ensure_test_tables_exist
  end

  def self.configure_database_connection(adapter)
    case adapter
    when "sqlite3"
      use_memory_database = ENV.fetch("MEMORY_DATABASE", "false") == "true"
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
        required_tables = [ "rails_pulse_routes", "rails_pulse_requests", "rails_pulse_queries", "rails_pulse_operations" ]

        if required_tables.all? { |table| ActiveRecord::Base.connection.table_exists?(table) }
          puts "Tables already exist" if ENV["VERBOSE"]
          return
        end

        puts "Creating Rails Pulse test tables..." if ENV["VERBOSE"]

        # Create Rails Pulse tables for testing
        ActiveRecord::Migration.suppress_messages do
          create_rails_pulse_test_schema
        end

        # Verify tables were created successfully
        missing_tables = required_tables.reject { |table| ActiveRecord::Base.connection.table_exists?(table) }
        if missing_tables.any?
          puts "Warning: Some tables were not created: #{missing_tables.join(', ')}" if ENV["VERBOSE"]
        else
          puts "Tables created successfully" if ENV["VERBOSE"]
        end
      rescue => e
        # If table creation fails, continue anyway but log details
        puts "Warning: Table creation failed: #{e.class} - #{e.message}" if ENV["VERBOSE"]
        puts "Backtrace: #{e.backtrace.first(3).join("\n")}" if ENV["VERBOSE"]
      end
    end
  end

  def self.create_rails_pulse_test_schema
    connection = ActiveRecord::Base.connection

    # Create routes table
    connection.create_table :rails_pulse_routes, force: true do |t|
      t.string :method, null: false
      t.string :path, null: false
      t.timestamps
    end

    # Add required index for routes uniqueness validation
    connection.add_index :rails_pulse_routes, [ :method, :path ], unique: true, name: "index_rails_pulse_routes_on_method_and_path"

    # Create requests table
    connection.create_table :rails_pulse_requests, force: true do |t|
      t.references :route, null: false, foreign_key: { to_table: :rails_pulse_routes }
      t.decimal :duration, precision: 15, scale: 6, null: false
      t.integer :status, null: false
      t.boolean :is_error, null: false, default: false
      t.string :request_uuid, null: false
      t.string :controller_action
      t.timestamp :occurred_at, null: false
      t.timestamps
    end

    # Create queries table
    connection.create_table :rails_pulse_queries, force: true do |t|
      t.text :normalized_sql, null: false
      t.timestamps
    end

    # Add required index for queries uniqueness validation
    connection.add_index :rails_pulse_queries, [ :normalized_sql ], unique: true, name: "index_rails_pulse_queries_on_normalized_sql"

    # Create operations table
    connection.create_table :rails_pulse_operations, force: true do |t|
      t.references :request, null: false, foreign_key: { to_table: :rails_pulse_requests }
      t.references :query, foreign_key: { to_table: :rails_pulse_queries }
      t.string :operation_type, null: false
      t.string :label, null: false
      t.decimal :duration, precision: 15, scale: 6, null: false
      t.string :codebase_location
      t.float :start_time, null: false, default: 0.0
      t.timestamp :occurred_at, null: false
      t.timestamps
    end
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

      # Configure MySQL-specific test settings
      configure_mysql_test_settings
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

  def self.configure_mysql_test_settings
    # Configure database cleaner for MySQL
    if defined?(DatabaseCleaner)
      DatabaseCleaner.strategy = :truncation
    end

    # Disable parallel testing in Rails
    if defined?(Minitest) && Minitest.respond_to?(:parallel_executor=)
      Minitest.parallel_executor = Minitest::Parallel::Executor.new(1)
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

  # Fast database cleanup using transactions
  def setup_test_database
    # Ensure tables exist before starting transaction
    DatabaseHelpers.ensure_test_tables_exist

    # Use transactions for cleanup instead of truncation
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
  end

  def teardown_test_database
    # Rollback transaction to clean up test data
    if ActiveRecord::Base.connection.transaction_open?
      ActiveRecord::Base.connection.rollback_transaction
    end
  end

  def using_memory_database?
    config = ActiveRecord::Base.connection_db_config.adapter
    database = ActiveRecord::Base.connection_db_config.database
    database == ":memory:" || config == "sqlite3"
  end
end
