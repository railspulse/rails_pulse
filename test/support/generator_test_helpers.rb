module GeneratorTestHelpers
  def schema_content
    File.read(File.expand_path("../../lib/generators/rails_pulse/templates/db/rails_pulse_schema.rb", __dir__))
  end

  def single_database_yml
    <<~YAML
      development:
        adapter: sqlite3
        database: db/development.sqlite3
    YAML
  end

  def separate_database_yml
    <<~YAML
      development:
        adapter: sqlite3
        database: db/development.sqlite3

      test:
        rails_pulse:
          adapter: sqlite3
          database: db/test_rails_pulse.sqlite3
          migrations_paths: db/rails_pulse_migrate
    YAML
  end

  def migration_content(name, class_name = nil)
    class_name ||= name.camelize
    <<~RUBY
      class #{class_name} < ActiveRecord::Migration[7.0]
        def change
          # Migration content for #{name}
        end
      end
    RUBY
  end

  def create_gem_migration(name, timestamp = "20251019000000")
    gem_path = gem_migrations_path
    FileUtils.mkdir_p(gem_path)
    filename = "#{timestamp}_#{name}.rb"
    File.write(File.join(gem_path, filename), migration_content(name))
    filename
  end

  def gem_migrations_path
    File.expand_path("../../db/rails_pulse_migrate", __dir__)
  end

  def setup_test_app_with_schema
    FileUtils.mkdir_p(File.join(destination_root, "db"))
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "db/rails_pulse_schema.rb"), schema_content)
  end

  def assert_migration(migration_path, &block)
    # Extract directory and filename from the path
    dir = File.dirname(migration_path)
    filename = File.basename(migration_path)

    # Find the migration file (may have timestamp prefix)
    full_dir = File.join(destination_root, dir)
    pattern = File.join(full_dir, "*_#{filename}")

    matching_files = Dir.glob(pattern)

    assert_predicate matching_files, :any?, "Expected migration matching #{migration_path} to exist, but does not"

    # Read and verify the content of the first matching file
    if block_given?
      content = File.read(matching_files.first)
      block.call(content)
    end
  end

  def assert_no_migration(migration_path)
    assert_no_file migration_path
  end
end
