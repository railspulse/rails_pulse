module RailsPulse
  module Generators
    class UpgradeGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path("templates", __dir__)

      desc "Upgrade Rails Pulse database schema to the latest version"

      class_option :database, type: :string, default: "detect",
                   desc: "Database setup: 'single', 'separate', or 'detect' (default)"

      def self.next_migration_number(path)
        next_migration_number = current_migration_number(path) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def check_current_installation
        @database_type = detect_database_setup

        say "Detected database setup: #{@database_type}", :green

        case @database_type
        when :single
          upgrade_single_database
        when :separate
          upgrade_separate_database
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

        if !tables_exist && File.exist?("db/rails_pulse_schema.rb")
          :schema_only
        elsif !tables_exist
          :not_installed
        elsif File.exist?("db/rails_pulse_migrate")
          :separate
        else
          :single
        end
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
        # Load the schema file to get the table names dynamically
        schema_file = File.join(Rails.root, "db/rails_pulse_schema.rb")

        if File.exist?(schema_file)
          # Read the schema file and extract the required_tables array
          schema_content = File.read(schema_file)

          # Extract the required_tables line using regex
          if match = schema_content.match(/required_tables\s*=\s*\[(.*?)\]/m)
            # Parse the array content, handling symbols and strings
            table_names = match[1].scan(/:(\w+)/).flatten
            return table_names.map(&:to_s)
          end
        end

        # Fallback to default table names if schema file parsing fails
        %w[rails_pulse_routes rails_pulse_queries rails_pulse_requests rails_pulse_operations rails_pulse_summaries]
      end

      def upgrade_single_database
        missing_columns = detect_missing_columns

        if missing_columns.empty?
          say "Rails Pulse is up to date! No migration needed.", :green
          return
        end

        # Format missing columns by table for the template
        missing_by_table = format_missing_columns_by_table(missing_columns)

        say "Creating upgrade migration for missing columns: #{missing_columns.keys.join(', ')}", :blue

        # Set instance variables for template
        @migration_version = ActiveRecord::Migration.current_version
        @missing_columns = missing_by_table

        migration_template(
          "migrations/upgrade_rails_pulse_tables.rb",
          "db/migrate/upgrade_rails_pulse_tables.rb"
        )

        say <<~MESSAGE

          Upgrade migration created successfully!

          Next steps:
          1. Run: rails db:migrate
          2. Restart your Rails server

          This migration will add: #{missing_columns.keys.join(', ')}

        MESSAGE
      end

      def upgrade_separate_database
        # For separate database, we'd need to check the schema file and generate migrations
        # in db/rails_pulse_migrate/ directory
        say "Separate database upgrade not implemented yet. Please check db/rails_pulse_schema.rb for updates.", :yellow
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

        # Get expected schema from the schema file
        expected_schema = get_expected_schema_from_file

        expected_schema.each do |table_name, columns|
          table_symbol = table_name.to_sym

          if connection.table_exists?(table_symbol)
            existing_columns = connection.columns(table_symbol).map(&:name)

            columns.each do |column_name, definition|
              unless existing_columns.include?(column_name)
                missing[column_name] = definition
              end
            end
          end
        end

        missing
      end

      def get_expected_schema_from_file
        schema_file = File.join(Rails.root, "db/rails_pulse_schema.rb")
        return {} unless File.exist?(schema_file)

        schema_content = File.read(schema_file)
        expected_columns = {}

        # Find each create_table block and parse its contents
        table_blocks = schema_content.scan(/connection\.create_table\s+:(\w+).*?do\s*\|t\|(.*?)(?:connection\.add_index|connection\.create_table|\z)/m)

        table_blocks.each do |table_name, table_block|
          columns = {}

          # Split the table block into lines and process each line
          table_block.split("\n").each do |line|
            # Match column definitions like: t.text :index_recommendations, comment: "..."
            if match = line.match(/t\.(\w+)\s+:([a-zA-Z_][a-zA-Z0-9_]*)(?:.*?comment:\s*"([^"]*)")?/)
              column_type, column_name, comment = match.captures

              # Skip timestamps and references as they're handled by Rails
              next if %w[timestamps references].include?(column_type)

              columns[column_name] = {
                type: column_type.to_sym,
                comment: comment
              }.compact
            end
          end

          expected_columns[table_name] = columns if columns.any?
        end

        expected_columns
      end

      def format_missing_columns_by_table(missing_columns)
        # The missing_columns are already organized by table from detect_missing_columns
        # but we need to restructure them for the template
        missing_by_table = {}

        # Get expected schema to find which table each missing column belongs to
        expected_schema = get_expected_schema_from_file

        expected_schema.each do |table_name, expected_columns|
          table_missing = {}

          expected_columns.each do |column_name, definition|
            if missing_columns.key?(column_name)
              table_missing[column_name] = definition
            end
          end

          missing_by_table[table_name] = table_missing if table_missing.any?
        end

        missing_by_table
      end
    end
  end
end
