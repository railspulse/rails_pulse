require_relative "base_methods"
require_relative "schema_parser"

module RailsPulse
  module Generators
    class UpgradeGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include BaseMethods

      source_root File.expand_path("templates", __dir__)

      desc "Upgrade Rails Pulse database schema to the latest version"

      class_option :database, type: :string, default: "detect",
                   desc: "Database setup: 'single', 'separate', or 'detect' (default)"

      def check_current_installation
        @database_type = detect_database_setup

        say "Detected database setup: #{@database_type}", :green

        case @database_type
        when :single
          upgrade_installation(migration_dir: "db/migrate", next_steps: single_db_next_steps)
        when :separate
          upgrade_installation(migration_dir: "db/rails_pulse_migrate", next_steps: separate_db_next_steps)
        when :schema_only
          offer_conversion_to_migrations
        when :not_installed
          say "Rails Pulse not detected. Run 'rails generate rails_pulse:install' first.", :red
          exit 1
        end
      end

      private

      def detect_database_setup
        # Override with command line option if provided
        return options[:database].to_sym if options[:database] != "detect"

        # Check for existing Rails Pulse tables
        tables_exist = rails_pulse_tables_exist?

        schema_path = File.join(root_path, "db/rails_pulse_schema.rb")

        if !tables_exist && File.exist?(schema_path)
          :schema_only
        elsif !tables_exist
          :not_installed
        elsif has_separate_database_config?
          :separate
        else
          :single
        end
      end

      def has_separate_database_config?
        config_path = File.join(root_path, "config/database.yml")

        return false unless File.exist?(config_path)

        require "yaml"
        db_config = YAML.safe_load(File.read(config_path), aliases: true)

        # Check if any environment has a rails_pulse database configuration
        db_config.values.any? { |env| env.is_a?(Hash) && env.key?("rails_pulse") }
      rescue Psych::SyntaxError, Psych::AliasesNotEnabled, Errno::ENOENT
        # If we can't read or parse the file, assume single database
        false
      end

      def rails_pulse_tables_exist?
        return false unless defined?(ActiveRecord::Base)

        connection = ActiveRecord::Base.connection
        required_tables = get_rails_pulse_table_names

        required_tables.all? { |table| connection.table_exists?(table) }
      rescue
        false
      end

      def get_rails_pulse_table_names
        schema_file = File.join(root_path, "db/rails_pulse_schema.rb")
        SchemaParser.new(schema_file).extract_table_names
      end

      # Shared upgrade logic for both single and separate database setups
      def upgrade_installation(migration_dir:, next_steps:)
        gem_migrations = get_gem_migrations
        existing_migrations = get_user_migrations(migration_dir)

        # Add origin comments to existing migrations that are missing them
        add_origin_comments(gem_migrations, existing_migrations, migration_dir)

        # Compare by migration name (without timestamp) to detect which are new
        existing_names = existing_migrations.map { |f| migration_name_without_timestamp(f) }
        new_migrations = gem_migrations.reject { |f| existing_names.include?(migration_name_without_timestamp(f)) }

        if new_migrations.any?
          say "Found #{new_migrations.size} new migration(s) to copy:", :blue
          new_migrations.each do |migration|
            say "  - #{migration_name_without_timestamp(migration)}", :blue
            copy_gem_migration_to(migration, migration_dir)
          end

          say "\nMigrations copied successfully!", :green
          say "\nNext steps:", :green
          next_steps.each { |step| say step }
        else
          upgrade_with_missing_columns(migration_dir: migration_dir, next_steps: next_steps)
        end
      end

      def upgrade_with_missing_columns(migration_dir:, next_steps:)
        missing_columns = detect_missing_columns

        if missing_columns.empty?
          say "Rails Pulse is up to date! No migration needed.", :green
          return
        end

        missing_by_table = format_missing_columns_by_table(missing_columns)

        say "Creating upgrade migration for missing columns: #{missing_columns.keys.join(', ')}", :blue

        @migration_version = ActiveRecord::Migration.current_version
        @missing_columns = missing_by_table

        migration_template(
          "migrations/upgrade_rails_pulse_tables.rb",
          "#{migration_dir}/upgrade_rails_pulse_tables.rb"
        )

        say <<~MESSAGE

          Upgrade migration created successfully!

          Next steps:
          #{next_steps.map { |s| "  #{s}" }.join("\n")}

          This migration will add: #{missing_columns.keys.join(', ')}

        MESSAGE
      end

      def single_db_next_steps
        [
          "1. Run: rails db:migrate",
          "2. Restart your Rails server"
        ]
      end

      def separate_db_next_steps
        [
          "1. Run migrations for the rails_pulse database:",
          "   rails db:migrate:rails_pulse",
          "2. Restart your Rails server"
        ]
      end

      def offer_conversion_to_migrations
        say <<~MESSAGE

          Rails Pulse schema detected but no tables found.

          To convert to single database setup:
          1. Run: rails generate rails_pulse:convert_to_migrations
          2. Run: rails db:migrate

          The schema file db/rails_pulse_schema.rb will remain as your single source of truth.

        MESSAGE
      end

      def detect_missing_columns
        return {} unless rails_pulse_tables_exist?

        connection = ActiveRecord::Base.connection
        missing = {}

        get_expected_schema_from_file.each do |table_name, columns|
          table_symbol = table_name.to_sym

          if connection.table_exists?(table_symbol)
            existing_columns = connection.columns(table_symbol).map(&:name)

            columns.each do |column_name, definition|
              missing[column_name] = definition unless existing_columns.include?(column_name)
            end
          end
        end

        missing
      end

      def get_expected_schema_from_file
        schema_file = File.join(root_path, "db/rails_pulse_schema.rb")
        SchemaParser.new(schema_file).extract_expected_schema
      end

      def format_missing_columns_by_table(missing_columns)
        missing_by_table = {}

        get_expected_schema_from_file.each do |table_name, expected_columns|
          table_missing = expected_columns.select { |col, _| missing_columns.key?(col) }
          missing_by_table[table_name] = table_missing if table_missing.any?
        end

        missing_by_table
      end

      def get_gem_migrations
        path = gem_migrations_path
        return [] unless File.directory?(path)

        Dir.glob("#{path}/*.rb").map { |f| File.basename(f) }
      end

      def get_user_migrations(directory)
        full_directory = File.join(root_path, directory)

        return [] unless File.directory?(full_directory)

        Dir.glob("#{full_directory}/*.rb").map { |f| File.basename(f) }
      end

      def migration_name_without_timestamp(filename)
        # "20260505000001_add_host_to_rails_pulse_routes.rb" -> "add_host_to_rails_pulse_routes"
        filename.sub(/^\d+_/, "").sub(/\.rb$/, "")
      end

      def copy_gem_migration_to(migration_name, destination)
        source_file = File.join(gem_migrations_path, migration_name)
        bare_name = migration_name_without_timestamp(migration_name)
        original_timestamp = migration_name.match(/^(\d+)/)[1]
        new_timestamp = next_migration_timestamp(destination)
        new_filename = "#{new_timestamp}_#{bare_name}.rb"
        destination_file = File.join(root_path, destination, new_filename)

        content = File.read(source_file)
        comment = "# This migration comes from rails_pulse (originally #{original_timestamp})\n"

        # Insert comment after any frozen_string_literal pragma, or at the top
        if content.match?(/\A# frozen_string_literal/)
          content = content.sub(/\A(# frozen_string_literal.*\n\n?)/, "\\1#{comment}")
        else
          content = comment + content
        end

        create_file destination_file, content
      end

      def next_migration_timestamp(directory)
        # Use Rails migration numbering: UTC timestamp format
        # Ensure we don't collide with existing migrations
        @migration_counter ||= 0
        full_directory = File.join(root_path, directory)
        existing = Dir.glob("#{full_directory}/*.rb").map { |f| File.basename(f).match(/^(\d+)/)[1].to_i }
        current_timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S").to_i + @migration_counter

        @migration_counter += 1
        [existing.max.to_i + 1, current_timestamp].max.to_s
      end

      def add_origin_comments(gem_migrations, existing_migrations, migration_dir)
        # Build a lookup of bare_name -> original timestamp from gem migrations
        gem_timestamps = {}
        gem_migrations.each do |f|
          bare = migration_name_without_timestamp(f)
          gem_timestamps[bare] = f.match(/^(\d+)/)[1]
        end

        full_directory = File.join(root_path, migration_dir)

        existing_migrations.each do |filename|
          bare = migration_name_without_timestamp(filename)
          original_timestamp = gem_timestamps[bare]
          next unless original_timestamp # Not a rails_pulse migration

          filepath = File.join(full_directory, filename)
          content = File.read(filepath)
          next if content.include?("# This migration comes from rails_pulse")

          comment = "# This migration comes from rails_pulse (originally #{original_timestamp})\n"

          if content.match?(/\A# frozen_string_literal/)
            content = content.sub(/\A(# frozen_string_literal.*\n\n?)/, "\\1#{comment}")
          else
            content = comment + content
          end

          File.write(filepath, content)
          say "  Added origin comment to #{filename}", :cyan
        end
      end
    end
  end
end
