# frozen_string_literal: true

require_relative "base_methods"

module RailsPulse
  module Generators
    class SchemaParser
      attr_reader :schema_path

      def initialize(schema_path)
        @schema_path = schema_path
      end

      # Extract table names from schema file
      # Returns array of table names from required_tables or fallback to default list
      def extract_table_names
        return BaseMethods::RAILS_PULSE_TABLES unless File.exist?(schema_path)

        schema_content = File.read(schema_path)
        if match = schema_content.match(/required_tables\s*=\s*\[(.*?)\]/m)
          table_names = match[1].scan(/:(\w+)/).flatten
          return table_names.map(&:to_s)
        end

        BaseMethods::RAILS_PULSE_TABLES
      end

      # Parse schema to extract expected columns for all tables
      # Returns hash of table_name => { column_name => { type:, comment: } }
      def extract_expected_schema
        return {} unless File.exist?(schema_path)

        schema_content = File.read(schema_path)
        expected_columns = {}

        # Find each create_table block and parse contents
        table_blocks = schema_content.scan(
          /connection\.create_table\s+:(\w+).*?do\s*\|t\|(.*?)(?:connection\.(?:add_index|create_table)|\z)/m
        )

        table_blocks.each do |table_name, table_block|
          columns = parse_table_columns(table_block)
          expected_columns[table_name] = columns if columns.any?
        end

        expected_columns
      end

      private

      # Parse column definitions from a table block
      # Returns hash of column_name => { type:, comment: }
      def parse_table_columns(table_block)
        columns = {}

        table_block.split("\n").each do |line|
          # Match column definitions: t.text :column_name, comment: "..."
          next unless match = line.match(/t\.(\w+)\s+:([a-zA-Z_][a-zA-Z0-9_]*)(?:.*?comment:\s*"([^"]*)")?/)

          column_type, column_name, comment = match.captures

          # Skip timestamps and references (Rails handles these)
          next if %w[timestamps references].include?(column_type)

          columns[column_name] = {
            type: column_type.to_sym,
            comment: comment
          }.compact
        end

        columns
      end
    end
  end
end
