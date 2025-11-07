module RailsPulse
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path("templates", __dir__)

      desc "Install Rails Pulse (recommended: use migrations for easier upgrades)"

      class_option :use_schema, type: :boolean, default: false,
                   desc: "Use schema file instead of migrations (legacy)"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def install_database_tables
        if use_schema?
          install_via_schema
        else
          install_via_migrations
        end
      end

      def copy_initializer
        copy_file "rails_pulse.rb", "config/initializers/rails_pulse.rb"
      end

      def display_post_install_message
        if use_schema?
          display_schema_message
        else
          display_migrations_message
        end
      end

      private

      def use_schema?
        options[:use_schema]
      end

      def install_via_schema
        say "Installing Rails Pulse using schema file (legacy)...", :yellow
        copy_file "db/rails_pulse_schema.rb", "db/rails_pulse_schema.rb"
      end

      def install_via_migrations
        say "Installing Rails Pulse using migrations (recommended)...", :green
        migration_template "migrations/create_rails_pulse_tables.rb",
                          "db/migrate/create_rails_pulse_tables.rb"
      end

      def display_schema_message
        say <<~MESSAGE

          Rails Pulse installation complete! (Schema-based setup - Legacy)

          Next steps:
          1. Run: rails db:prepare (creates database and loads schema)
          2. Restart your Rails server

          Note: Future upgrades may require manual schema synchronization.
          Consider using migrations-based installation for easier upgrades:
            rails generate rails_pulse:install

        MESSAGE
      end

      def display_migrations_message
        say <<~MESSAGE

          Rails Pulse installation complete!

          Next steps:
          1. Run: rails db:migrate
          2. Restart your Rails server

          For upgrades, run: rails generate rails_pulse:upgrade
          This will detect and generate any necessary schema updates.

        MESSAGE
      end
    end
  end
end
