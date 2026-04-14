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

    output = mock_tables_exist do
      run_generator([], {})
    end

    assert_match(/Detected database setup: separate/, output)
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
    # Create a simple object that has tables with all columns including tags
    connection = Object.new
    schema = complete_schema_columns

    def connection.table_exists?(_table)
      true
    end

    # Return columns based on the specific table being queried
    connection.define_singleton_method(:columns) do |table|
      table_name = table.to_s.to_sym
      columns = schema[table_name] || []
      columns.map { |col| OpenStruct.new(name: col) }
    end

    ActiveRecord::Base.stubs(:connection).returns(connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    result
  end

  def mock_no_tables_exist
    # Create a simple object that responds to table_exists? with false
    connection = Object.new
    def connection.table_exists?(_table)
      false
    end

    ActiveRecord::Base.stubs(:connection).returns(connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    result
  end

  def mock_tables_with_missing_columns
    # Create a simple object that has tables but missing tag columns
    connection = Object.new
    schema = schema_without_tags

    def connection.table_exists?(_table)
      true
    end

    # Return columns based on the specific table being queried (without tags)
    connection.define_singleton_method(:columns) do |table|
      table_name = table.to_s.to_sym
      columns = schema[table_name] || []
      columns.map { |col| OpenStruct.new(name: col) }
    end

    ActiveRecord::Base.stubs(:connection).returns(connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    result
  end

  def mock_complete_tables
    # Create a simple object that has complete tables with tags
    connection = Object.new
    schema = complete_schema_columns

    def connection.table_exists?(_table)
      true
    end

    # Return columns based on the specific table being queried
    connection.define_singleton_method(:columns) do |table|
      table_name = table.to_s.to_sym
      columns = schema[table_name] || []
      columns.map { |col| OpenStruct.new(name: col) }
    end

    ActiveRecord::Base.stubs(:connection).returns(connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    result
  end
end
