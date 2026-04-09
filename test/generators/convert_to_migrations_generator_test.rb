require "test_helper"
require "generators/rails_pulse/convert_to_migrations_generator"
require_relative "../support/generator_test_helpers"

class ConvertToMigrationsGeneratorTest < Rails::Generators::TestCase
  include GeneratorTestHelpers

  tests RailsPulse::Generators::ConvertToMigrationsGenerator

  def destination_root
    @destination_root ||= File.expand_path("../tmp/convert_generator_test/#{name}", __dir__)
  end

  setup do
    prepare_destination
    setup_test_app_with_schema
  end

  # Schema File Validation Tests

  test "exits with error when schema file missing" do
    FileUtils.rm_f(File.join(destination_root, "db/rails_pulse_schema.rb"))

    assert_raises SystemExit do
      run_generator
    end
  end

  test "exits with message when tables already exist" do
    assert_raises SystemExit do
      mock_tables_exist do
        run_generator
      end
    end
  end

  # Migration Creation Tests

  test "creates migration when schema exists and no tables" do
    mock_no_tables_exist do
      run_generator
    end

    assert_migration "db/migrate/install_rails_pulse_tables.rb" do |content|
      assert_match(/class InstallRailsPulseTables/, content)
      assert_match(/RailsPulse::Schema.call/, content)
    end
  end

  test "migration includes proper Rails version" do
    mock_no_tables_exist do
      run_generator
    end

    assert_migration "db/migrate/install_rails_pulse_tables.rb" do |content|
      # Should include the ActiveRecord::Migration version
      assert_match(/ActiveRecord::Migration/, content)
    end
  end

  # Output Message Tests

  test "displays conversion progress message" do
    output = mock_no_tables_exist do
      run_generator
    end

    assert_match(/Converting db\/rails_pulse_schema\.rb to migration/, output)
  end

  test "displays completion message with next steps" do
    output = mock_no_tables_exist do
      run_generator
    end

    assert_match(/Conversion complete/, output)
    assert_match(/rails db:migrate/, output)
    assert_match(/Restart your Rails server/, output)
  end

  # Edge Cases

  test "handles empty schema file gracefully" do
    schema_path = File.join(destination_root, "db/rails_pulse_schema.rb")
    File.write(schema_path, "")

    mock_no_tables_exist do
      run_generator
    end

    # Should still create migration even with empty schema
    assert_migration "db/migrate/install_rails_pulse_tables.rb"
  end

  test "migration template loads schema from correct path" do
    mock_no_tables_exist do
      run_generator
    end

    assert_migration "db/migrate/install_rails_pulse_tables.rb" do |content|
      # Should reference the schema file location
      assert_match(/rails_pulse_schema/, content)
    end
  end

  private

  def mock_tables_exist
    connection = Object.new
    def connection.table_exists?(_table)
      true
    end

    ActiveRecord::Base.stubs(:connection).returns(connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    result
  end

  def mock_no_tables_exist
    connection = Object.new
    def connection.table_exists?(_table)
      false
    end

    ActiveRecord::Base.stubs(:connection).returns(connection)
    result = yield if block_given?
    ActiveRecord::Base.unstub(:connection)
    result
  end
end
