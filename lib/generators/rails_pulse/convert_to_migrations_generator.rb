require_relative "base_methods"

module RailsPulse
  module Generators
    class ConvertToMigrationsGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include BaseMethods

      source_root File.expand_path("templates", __dir__)

      desc "Convert Rails Pulse schema file to migrations for single database setup"

      def check_schema_file
        schema_path = File.join(root_path, "db/rails_pulse_schema.rb")

        unless File.exist?(schema_path)
          say "No db/rails_pulse_schema.rb file found. Run 'rails generate rails_pulse:install' first.", :red
          exit 1
        end

        if rails_pulse_tables_exist?
          say "Rails Pulse tables already exist. No conversion needed.", :yellow
          say "Use 'rails generate rails_pulse:upgrade' to update existing installation.", :blue
          exit 0
        end
      end

      def create_conversion_migration
        say "Converting db/rails_pulse_schema.rb to migration...", :green

        migration_template(
          "migrations/install_rails_pulse_tables.rb",
          "db/migrate/install_rails_pulse_tables.rb"
        )
      end

      def display_completion_message
        say <<~MESSAGE

          Conversion complete!

          Next steps:
          1. Run: rails db:migrate
          2. Restart your Rails server

          The schema file db/rails_pulse_schema.rb remains as your single source of truth.
          Future Rails Pulse updates will come as regular migrations in db/migrate/

        MESSAGE
      end
    end
  end
end
