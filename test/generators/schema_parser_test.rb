require "test_helper"
require "generators/rails_pulse/schema_parser"

module RailsPulse
  module Generators
    class SchemaParserTest < ActiveSupport::TestCase
      def setup
        @schema_path = File.expand_path("../../lib/generators/rails_pulse/templates/db/rails_pulse_schema.rb", __dir__)
        @parser = SchemaParser.new(@schema_path)
      end

      # Table Name Extraction Tests

      test "extracts table names from schema file" do
        table_names = @parser.extract_table_names

        assert_kind_of Array, table_names
        assert_includes table_names, "rails_pulse_routes"
        assert_includes table_names, "rails_pulse_queries"
        assert_includes table_names, "rails_pulse_requests"
        assert_includes table_names, "rails_pulse_operations"
        assert_includes table_names, "rails_pulse_jobs"
        assert_includes table_names, "rails_pulse_job_runs"
        assert_includes table_names, "rails_pulse_summaries"
      end

      test "returns default table names when schema file missing" do
        parser = SchemaParser.new("/nonexistent/path")
        table_names = parser.extract_table_names

        assert_equal BaseMethods::RAILS_PULSE_TABLES, table_names
      end

      # Schema Extraction Tests

      test "extracts expected schema with column types" do
        schema = @parser.extract_expected_schema

        assert_kind_of Hash, schema
        assert schema.key?("rails_pulse_routes")

        routes_columns = schema["rails_pulse_routes"]

        assert_includes routes_columns.keys, "method"
        assert_includes routes_columns.keys, "path"
        assert_includes routes_columns.keys, "tags"
      end

      test "parses column types correctly" do
        schema = @parser.extract_expected_schema
        routes = schema["rails_pulse_routes"]

        assert_equal :string, routes["method"][:type]
        assert_equal :text, routes["tags"][:type]
      end

      test "preserves column comments when present" do
        schema = @parser.extract_expected_schema
        routes = schema["rails_pulse_routes"]

        # Check that comment exists for columns that have them
        assert_predicate routes["method"][:comment], :present?
        assert_match(/HTTP method/, routes["method"][:comment])
      end

      test "skips timestamps columns" do
        schema = @parser.extract_expected_schema
        routes = schema["rails_pulse_routes"]

        refute_includes routes.keys, "created_at"
        refute_includes routes.keys, "updated_at"
      end

      test "skips references columns" do
        schema = @parser.extract_expected_schema

        # Check across multiple tables that have foreign keys
        schema.values.each do |table_columns|
          # Should not have column type 'references' or 'belongs_to'
          table_columns.each do |_name, definition|
            refute_equal :references, definition[:type]
            refute_equal :belongs_to, definition[:type]
          end
        end
      end

      # Edge Cases

      test "handles empty schema file" do
        Dir.mktmpdir do |dir|
          empty_schema = File.join(dir, "empty.rb")
          File.write(empty_schema, "")

          parser = SchemaParser.new(empty_schema)
          schema = parser.extract_expected_schema

          assert_empty schema
        end
      end

      test "handles malformed schema file gracefully" do
        Dir.mktmpdir do |dir|
          bad_schema = File.join(dir, "bad.rb")
          File.write(bad_schema, "not valid ruby code {{{")

          parser = SchemaParser.new(bad_schema)

          # Should not raise, should return empty hash
          assert_nothing_raised do
            schema = parser.extract_expected_schema

            assert_kind_of Hash, schema
          end
        end
      end

      test "returns empty hash for nonexistent file" do
        parser = SchemaParser.new("/nonexistent/file.rb")
        schema = parser.extract_expected_schema

        assert_kind_of Hash, schema
        assert_empty schema
      end
    end
  end
end
