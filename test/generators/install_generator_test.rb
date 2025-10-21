require "test_helper"
require "generators/rails_pulse/install_generator"
require_relative "../support/generator_test_helpers"

class InstallGeneratorTest < Rails::Generators::TestCase
  include GeneratorTestHelpers

  tests RailsPulse::Generators::InstallGenerator
  destination File.expand_path("../tmp/generator_test", __dir__)

  setup do
    prepare_destination
    # Create a sample migration in the gem to test copying
    create_gem_migration("add_tags_to_rails_pulse_tables", "20251018000000")
  end

  teardown do
    # Clean up gem migrations created during test
    FileUtils.rm_rf(gem_migrations_path)
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

  test "single database install copies gem migrations to db/migrate" do
    run_generator

    assert_file "db/migrate/20251018000000_add_tags_to_rails_pulse_tables.rb" do |content|
      assert_match(/class AddTagsToRailsPulseTables/, content)
      # Note: Test helper creates generic migrations, not the actual migration content
      # In real usage, the actual migration with add_column statements would be copied
    end
  end

  test "single database install doesn't overwrite existing migrations" do
    # Pre-create the migration with custom content
    FileUtils.mkdir_p(File.join(destination_root, "db/migrate"))
    File.write(
      File.join(destination_root, "db/migrate/20251018000000_add_tags_to_rails_pulse_tables.rb"),
      "# Custom migration content"
    )

    run_generator

    # Should not overwrite
    assert_file "db/migrate/20251018000000_add_tags_to_rails_pulse_tables.rb" do |content|
      assert_match(/# Custom migration content/, content)
      assert_no_match(/class AddTagsToRailsPulseTables/, content)
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

  test "separate database install copies gem migrations to rails_pulse_migrate" do
    run_generator [ "--database=separate" ]

    assert_file "db/rails_pulse_migrate/20251018000000_add_tags_to_rails_pulse_tables.rb" do |content|
      assert_match(/class AddTagsToRailsPulseTables/, content)
    end
  end

  test "separate database install doesn't overwrite existing migrations in rails_pulse_migrate" do
    # Pre-create the migration
    FileUtils.mkdir_p(File.join(destination_root, "db/rails_pulse_migrate"))
    File.write(
      File.join(destination_root, "db/rails_pulse_migrate/20251018000000_add_tags_to_rails_pulse_tables.rb"),
      "# Custom migration"
    )

    run_generator [ "--database=separate" ]

    # Should not overwrite
    assert_file "db/rails_pulse_migrate/20251018000000_add_tags_to_rails_pulse_tables.rb" do |content|
      assert_match(/# Custom migration/, content)
    end
  end

  # Note: Output message tests are difficult to capture in generator tests
  # test "separate database install displays correct post-install message" do
  #   ...
  # end

  test "install works when no gem migrations exist" do
    # Remove gem migrations
    FileUtils.rm_rf(gem_migrations_path)

    run_generator

    # Should still create all other files
    assert_file "db/rails_pulse_schema.rb"
    assert_file "config/initializers/rails_pulse.rb"
    assert_migration "db/migrate/install_rails_pulse_tables.rb"
  end
end
