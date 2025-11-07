module RailsPulse
  module Generators
    class MigrationsGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path("migrations", __dir__)

      desc "Install Rails Pulse migrations"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_migrations
        migration_template "create_rails_pulse_tables.rb",
                          "db/migrate/create_rails_pulse_tables.rb"
      end

      def display_post_install_message
        say <<~MESSAGE

          Rails Pulse migrations have been installed!

          Next steps:
          1. Run: rails db:migrate
          2. Restart your Rails server

          For separate database setup, add to config/database.yml:
            #{environment}:
              rails_pulse:
                <<: *default
                database: storage/#{environment}_rails_pulse.sqlite3
                migrations_paths: db/migrate

        MESSAGE
      end

      private

      def environment
        Rails.env.production? ? "production" : "development"
      end
    end
  end
end
