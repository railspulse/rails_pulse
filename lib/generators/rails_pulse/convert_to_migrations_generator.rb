module RailsPulse
  module Generators
    class ConvertToMigrationsGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path("templates", __dir__)

      desc "Convert Rails Pulse schema file to migrations for single database setup"

      def self.next_migration_number(path)
        next_migration_number = current_migration_number(path) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def check_schema_file
        unless File.exist?("db/rails_pulse_schema.rb")
          # Only show message in non-test environments to reduce test noise
          unless Rails.env.test?
            say "No db/rails_pulse_schema.rb file found. Run 'rails generate rails_pulse:install' first.", :red
            exit 1
          else
            return false
          end
        end

        if rails_pulse_tables_exist?
          unless Rails.env.test?
            say "Rails Pulse tables already exist. No conversion needed.", :yellow
            say "Use 'rails generate rails_pulse:upgrade' to update existing installation.", :blue
            exit 0
          else
            return false
          end
        end

        true
      end

      def create_conversion_migration
        # Only create migration if schema file check passes
        return unless check_schema_file

        say "Converting db/rails_pulse_schema.rb to migration...", :green

        migration_template(
          "migrations/install_rails_pulse_tables.rb",
          "db/migrate/install_rails_pulse_tables.rb"
        )
      end

      def display_completion_message
        # Only display completion message if migration was created
        return unless File.exist?("db/rails_pulse_schema.rb")

        say <<~MESSAGE

          Conversion complete!

          Next steps:
          1. Run: rails db:migrate
          2. Restart your Rails server

          The schema file db/rails_pulse_schema.rb remains as your single source of truth.
          Future Rails Pulse updates will come as regular migrations in db/migrate/

        MESSAGE
      end

      private

      def rails_pulse_tables_exist?
        return false unless defined?(ActiveRecord::Base)

        connection = ActiveRecord::Base.connection
        %w[rails_pulse_routes rails_pulse_queries rails_pulse_requests rails_pulse_operations rails_pulse_summaries]
          .all? { |table| connection.table_exists?(table) }
      rescue
        false
      end
    end
  end
end
