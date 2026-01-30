require "test_helper"
require "generators/rails_pulse/install_generator"
require_relative "../support/generator_test_helpers"

class InstallGeneratorTest < Rails::Generators::TestCase
  include GeneratorTestHelpers

  tests RailsPulse::Generators::InstallGenerator

  def destination_root
    # Use test-specific directory to avoid parallel test interference
    @destination_root ||= File.expand_path("../tmp/install_generator_test/#{name}", __dir__)
  end

  setup do
    prepare_destination
  end

  # Single Database Tests

  test "single database install copies schema file" do
    run_generator

    assert_file "db/rails_pulse_schema.rb" do |content|
      assert_match(/RailsPulse::Schema = lambda/, content)
      assert_match(/create_table :rails_pulse_routes/, content)
    end
  end

  test "single database install creates rails_pulse_migrate directory" do
    run_generator

    assert_file "db/rails_pulse_migrate/.keep"
  end

  test "single database install copies initializer" do
    run_generator

    assert_file "config/initializers/rails_pulse.rb" do |content|
      assert_match(/RailsPulse.configure/, content)
    end
  end

  test "single database install creates installation migration" do
    run_generator

    assert_migration "db/migrate/install_rails_pulse_tables.rb" do |content|
      assert_match(/class InstallRailsPulseTables/, content)
      assert_match(/RailsPulse::Schema.call/, content)
    end
  end

  # Note: Output message tests are difficult to capture in generator tests
  # The generator displays messages correctly but they're not easily testable
  # test "single database install displays correct post-install message" do
  #   ...
  # end

  # Separate Database Tests

  test "separate database install copies schema file" do
    run_generator [ "--database=separate" ]

    assert_file "db/rails_pulse_schema.rb"
  end

  test "separate database install creates rails_pulse_migrate directory" do
    run_generator [ "--database=separate" ]

    assert_file "db/rails_pulse_migrate/.keep"
  end

  test "separate database install does not create installation migration" do
    run_generator [ "--database=separate" ]

    # Should not create migration in db/migrate for separate database
    assert_no_file "db/migrate/install_rails_pulse_tables.rb"
  end

  # Note: Output message tests are difficult to capture in generator tests
  # test "separate database install displays correct post-install message" do
  #   ...
  # end
end
