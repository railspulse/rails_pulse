module RailsPulse
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path("templates", __dir__)

      desc "Install Rails Pulse with flexible database setup options"

      class_option :database, type: :string, default: "single",
                   desc: "Database setup: 'single' (default) or 'separate'"

      def self.next_migration_number(path)
        next_migration_number = current_migration_number(path) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_schema
        copy_file "db/rails_pulse_schema.rb", "db/rails_pulse_schema.rb"
      end

      def create_migration_directory
        create_file "db/rails_pulse_migrate/.keep"
      end

      def copy_gem_migrations
        gem_migrations_path = File.expand_path("../../../db/rails_pulse_migrate", __dir__)
        destination_dir = separate_database? ? "db/rails_pulse_migrate" : "db/migrate"

        if File.directory?(gem_migrations_path)
          Dir.glob("#{gem_migrations_path}/*.rb").each do |migration_file|
            migration_name = File.basename(migration_file)
            destination_path = File.join(destination_dir, migration_name)

            # Only copy if it doesn't already exist in the destination
            # Use File.join with destination_root to check the actual location
            full_destination_path = File.join(destination_root, destination_path)
            unless File.exist?(full_destination_path)
              copy_file migration_file, destination_path
            end
          end
        end
      end

      def copy_initializer
        copy_file "rails_pulse.rb", "config/initializers/rails_pulse.rb"
      end

      def setup_database_configuration
        if separate_database?
          create_separate_database_setup
        else
          create_single_database_setup
        end
      end

      def display_post_install_message
        if separate_database?
          display_separate_database_message
        else
          display_single_database_message
        end
      end

      private

      def separate_database?
        options[:database] == "separate"
      end

      def create_separate_database_setup
        say "Setting up separate database configuration...", :green

        # Migration directory already created by create_migration_directory
        # Could add database.yml configuration here if needed
        # For now, users will configure manually
      end

      def create_single_database_setup
        say "Setting up single database configuration...", :green

        # Create a migration that loads the schema
        migration_template(
          "migrations/install_rails_pulse_tables.rb",
          "db/migrate/install_rails_pulse_tables.rb"
        )
      end

      def display_separate_database_message
        say <<~MESSAGE

          Rails Pulse installation complete! (Separate Database Setup)

          Next steps:
          1. Add Rails Pulse database configuration to config/database.yml:

             #{Rails.env}:
               rails_pulse:
                 <<: *default
                 database: storage/#{Rails.env}_rails_pulse.sqlite3
                 migrations_paths: db/rails_pulse_migrate

          2. Run: rails db:prepare (creates database and loads schema)
          3. Restart your Rails server

          The schema file db/rails_pulse_schema.rb is your single source of truth.
          Future upgrades will automatically copy new migrations to db/rails_pulse_migrate/

        MESSAGE
      end

      def display_single_database_message
        say <<~MESSAGE

          Rails Pulse installation complete! (Single Database Setup)

          Next steps:
          1. Run: rails db:migrate (creates Rails Pulse tables in your main database)
          2. Restart your Rails server

          The schema file db/rails_pulse_schema.rb is your single source of truth.
          Future upgrades will automatically copy new migrations to db/migrate/

          Note: The installation migration loads from db/rails_pulse_schema.rb
          and includes all current Rails Pulse tables and columns.

        MESSAGE
      end
    end
  end
end
