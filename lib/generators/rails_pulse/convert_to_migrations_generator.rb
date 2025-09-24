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
          2. Delete: db/rails_pulse_schema.rb (no longer needed)
          3. Remove db/rails_pulse_migrate/ directory if it exists
          4. Restart your Rails server

          Future Rails Pulse updates will come as regular migrations.

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
