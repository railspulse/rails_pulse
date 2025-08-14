module RailsPulse
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install Rails Pulse with schema-based setup"
      
      def copy_schema
        copy_file "db/rails_pulse_schema.rb", "db/rails_pulse_schema.rb"
      end

      def copy_initializer
        copy_file "rails_pulse.rb", "config/initializers/rails_pulse.rb"
      end

      def create_database_migration_paths
        if separate_database?
          create_file "db/rails_pulse_migrate/.keep"
        end
      end

      def display_post_install_message
        say <<~MESSAGE

          Rails Pulse installation complete!

          Next steps:
          1. Configure your database in config/database.yml (see README for examples)
          2. Run: rails db:prepare (creates database and loads schema)
          3. Restart your Rails server

          For separate database setup, add to config/database.yml:
            #{environment}:
              rails_pulse:
                <<: *default
                database: storage/#{environment}_rails_pulse.sqlite3
                migrations_paths: db/rails_pulse_migrate

        MESSAGE
      end

      private

      def separate_database?
        # Could make this configurable via options
        false
      end

      def environment
        Rails.env.production? ? "production" : "development"
      end
    end
  end
end
