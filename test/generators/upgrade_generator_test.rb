require "test_helper"
require "generators/rails_pulse/upgrade_generator"
require_relative "../support/generator_test_helpers"
require "ostruct"

class UpgradeGeneratorTest < Rails::Generators::TestCase
  include GeneratorTestHelpers

  tests RailsPulse::Generators::UpgradeGenerator

  def destination_root
    # Use test-specific directory to avoid parallel test interference
    @destination_root ||= File.expand_path("../tmp/upgrade_generator_test/#{name}", __dir__)
  end

  setup do
    prepare_destination
    setup_test_app_with_schema

    # Stub the generator to use test-specific gem migrations path
    RailsPulse::Generators::UpgradeGenerator.any_instance.stubs(:gem_migrations_path).returns(gem_migrations_path)
  end

  teardown do
    FileUtils.rm_rf(gem_migrations_path)
    RailsPulse::Generators::UpgradeGenerator.any_instance.unstub(:gem_migrations_path)
  end

  # Database Detection Tests

  test "detects single database setup by default" do
    File.write(File.join(destination_root, "config/database.yml"), single_database_yml)

    output = mock_tables_exist do
      run_generator([], {})
    end

    assert_match(/Detected database setup: single/, output)
  end

test "detects separate database setup from database.yml" do
    File.write(File.join(destination_root, "config/database.yml"), separate_database_yml)

    output = run_generator([], { database: "separate" })

    assert_match(/Detected database setup: separate/, output)
  end

  test "detects single database setup when database.yml uses YAML aliases" do
    File.write(File.join(destination_root, "config/database.yml"), single_database_yml_with_aliases)

    output = mock_tables_exist do
      run_generator([], {})
    end

    assert_match(/Detected database setup: single/, output)
  end

  test "detects separate database setup when database.yml uses YAML aliases" do
    File.write(File.join(destination_root, "config/database.yml"), separate_database_yml_with_aliases)

    # Tables exist only on the ApplicationRecord connection (separate DB), not on
    # the primary ActiveRecord::Base connection — the real separate-database scenario.
    output = mock_tables_exist_on_app_record_only do
      run_generator([], {})
    end

    assert_match(/Detected database setup: separate/, output)
  end

  test "auto-detects separate database without explicit flag when tables are on separate connection" do
    # This is the regression test for issue #166 Bug 1: the generator was returning
    # :schema_only for separate-DB users because it checked ActiveRecord::Base.connection
    # (primary DB, no tables) before checking has_separate_database_config?.
    File.write(File.join(destination_root, "config/database.yml"), separate_database_yml)

    output = mock_tables_exist_on_app_record_only do
      run_generator([], {})
    end

    assert_match(/Detected database setup: separate/, output)
    assert_no_match(/schema detected but no tables found/, output)
  end

  test "detects schema_only when schema exists but no tables" do
    output = mock_no_tables_exist do
      run_generator([], {})
    end

    assert_match(/schema detected but no tables found/, output)
  end

  test "detects not_installed when no schema and no tables" do
    FileUtils.rm_f(File.join(destination_root, "db/rails_pulse_schema.rb"))

    assert_raises SystemExit do
      mock_no_tables_exist do
        run_generator([], {})
      end
    end
  end

  # Single Database Migration Copying Tests

  test "single database upgrade copies new migrations from gem" do
    File.write(File.join(destination_root, "config/database.yml"), single_database_yml)
    create_gem_migration("add_new_feature", "20251019000000")

    output = mock_tables_exist do
      run_generator([], {})
    end

    assert_match(/Found 1 new migration/, output)
    assert_file "db/migrate/20251019000000_add_new_feature.rb"
  end

  test "single database upgrade copies multiple new migrations" do
    File.write(File.join(destination_root, "config/database.yml"), single_database_yml)
    create_gem_migration("add_feature_one", "20251019000000")
    create_gem_migration("add_feature_two", "20251019000001")

    output = mock_tables_exist do
      run_generator([], {})
    end

    assert_match(/Found 2 new migration/, output)
    assert_file "db/migrate/20251019000000_add_feature_one.rb"
    assert_file "db/migrate/20251019000001_add_feature_two.rb"
  end

  test "single database upgrade doesn't copy existing migrations" do
    File.write(File.join(destination_root, "config/database.yml"), single_database_yml)
    create_gem_migration("add_tags_to_rails_pulse_tables", "20251018000000")

    # Pre-create the migration in user's app
    FileUtils.mkdir_p(File.join(destination_root, "db/migrate"))
    File.write(
      File.join(destination_root, "db/migrate/20251018000000_add_tags_to_rails_pulse_tables.rb"),
      "# Already migrated"
    )

    mock_tables_exist do
      run_generator([], {})
    end

    # File should not be overwritten - verify content is unchanged
    assert_file "db/migrate/20251018000000_add_tags_to_rails_pulse_tables.rb" do |content|
      assert_match(/# Already migrated/, content)
      assert_no_match(/add_column/, content)
    end
  end

# Separate Database Migration Copying Tests

test "separate database upgrade copies migrations to rails_pulse_migrate" do
    File.write(File.join(destination_root, "config/database.yml"), separate_database_yml)
    create_gem_migration("add_new_feature", "20251019000000")

    output = mock_tables_exist do
      run_generator([], { database: "separate" })
    end

    assert_match(/Found 1 new migration/, output)
    assert_file "db/rails_pulse_migrate/20251019000000_add_new_feature.rb"
    assert_match(/rails db:migrate:rails_pulse/, output)
  end

  # Missing Column Detection Tests

  test "generates migration for missing columns when no new migrations" do
    File.write(File.join(destination_root, "config/database.yml"), single_database_yml)

    output = mock_tables_with_missing_columns do
      run_generator([], {})
    end

    assert_match(/Creating upgrade migration for missing columns/, output)
    assert_migration "db/migrate/upgrade_rails_pulse_tables.rb" do |content|
      assert_match(/add_column :rails_pulse_routes, :tags, :text/, content)
    end
  end

  test "separate database generates migration for missing columns" do
    File.write(File.join(destination_root, "config/database.yml"), separate_database_yml)

    output = mock_tables_with_missing_columns do
      run_generator([], { database: "separate" })
    end

    assert_migration "db/rails_pulse_migrate/upgrade_rails_pulse_tables.rb" do |content|
      assert_match(/add_column :rails_pulse_routes, :tags, :text/, content)
    end
  end

  # Helper Methods

  private

  def mock_tables_exist
    connection = build_connection_with_tables(complete_schema_columns)
    ActiveRecord::Base.stubs(:connection).returns(connection)
    RailsPulse::ApplicationRecord.stubs(:connection).returns(connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    RailsPulse::ApplicationRecord.unstub(:connection)
    result
  end

  # Simulates a separate-database user: Rails Pulse tables exist only on the
  # ApplicationRecord connection, not on the primary ActiveRecord::Base connection.
  # This is the scenario that previously triggered the :schema_only false positive.
  def mock_tables_exist_on_app_record_only
    tables_connection = build_connection_with_tables(complete_schema_columns)
    no_tables_connection = build_connection_without_tables

    ActiveRecord::Base.stubs(:connection).returns(no_tables_connection)
    RailsPulse::ApplicationRecord.stubs(:connection).returns(tables_connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    RailsPulse::ApplicationRecord.unstub(:connection)
    result
  end

  def mock_no_tables_exist
    connection = build_connection_without_tables
    ActiveRecord::Base.stubs(:connection).returns(connection)
    RailsPulse::ApplicationRecord.stubs(:connection).returns(connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    RailsPulse::ApplicationRecord.unstub(:connection)
    result
  end

  def mock_tables_with_missing_columns
    connection = build_connection_with_tables(schema_without_tags)
    ActiveRecord::Base.stubs(:connection).returns(connection)
    RailsPulse::ApplicationRecord.stubs(:connection).returns(connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    RailsPulse::ApplicationRecord.unstub(:connection)
    result
  end

  def mock_complete_tables
    connection = build_connection_with_tables(complete_schema_columns)
    ActiveRecord::Base.stubs(:connection).returns(connection)
    RailsPulse::ApplicationRecord.stubs(:connection).returns(connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    RailsPulse::ApplicationRecord.unstub(:connection)
    result
  end

  def build_connection_with_tables(schema)
    connection = Object.new
    def connection.table_exists?(_table) = true
    connection.define_singleton_method(:columns) do |table|
      (schema[table.to_s.to_sym] || []).map { |col| OpenStruct.new(name: col) }
    end
    connection
  end

  def build_connection_without_tables
    connection = Object.new
    def connection.table_exists?(_table) = false
    connection
  end
end
