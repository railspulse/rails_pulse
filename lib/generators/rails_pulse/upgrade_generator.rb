module RailsPulse
  module Generators
    class UpgradeGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path("upgrade_migrations", __dir__)

      desc "Upgrade existing Rails Pulse installation to latest schema"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def check_tables_exist
        unless tables_exist?
          say "Rails Pulse tables not found. Please run 'rails generate rails_pulse:migrations' for a fresh installation.", :red
          exit 1
        end
      end

      def copy_upgrade_migrations
        # Check which columns are missing and generate appropriate migrations
        if needs_tags_migration?
          migration_template "add_tags_to_rails_pulse_tables.rb",
                            "db/migrate/add_tags_to_rails_pulse_tables.rb"
          say "Generated migration to add tags columns", :green
        end

        if needs_query_analysis_columns?
          migration_template "add_query_analysis_columns.rb",
                            "db/migrate/add_query_analysis_columns.rb"
          say "Generated migration to add query analysis columns", :green
        end

        if needs_summaries_table?
          migration_template "create_rails_pulse_summaries.rb",
                            "db/migrate/create_rails_pulse_summaries.rb"
          say "Generated migration to create summaries table", :green
        end
      end

      def display_post_install_message
        say <<~MESSAGE

          Rails Pulse upgrade migrations have been generated!

          Next steps:
          1. Review the generated migrations in db/migrate/
          2. Run: rails db:migrate
          3. Restart your Rails server

        MESSAGE
      end

      private

      def tables_exist?
        connection.table_exists?(:rails_pulse_routes) &&
          connection.table_exists?(:rails_pulse_requests)
      end

      def needs_tags_migration?
        !connection.column_exists?(:rails_pulse_routes, :tags) ||
          !connection.column_exists?(:rails_pulse_queries, :tags) ||
          !connection.column_exists?(:rails_pulse_requests, :tags)
      end

      def needs_query_analysis_columns?
        !connection.column_exists?(:rails_pulse_queries, :analyzed_at) ||
          !connection.column_exists?(:rails_pulse_queries, :explain_plan)
      end

      def needs_summaries_table?
        !connection.table_exists?(:rails_pulse_summaries)
      end

      def connection
        @connection ||= if defined?(RailsPulse::ApplicationRecord)
                         RailsPulse::ApplicationRecord.connection
                       else
                         ActiveRecord::Base.connection
                       end
      end
    end
  end
end
