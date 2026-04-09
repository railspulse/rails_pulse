require "test_helper"

module RailsPulse
  module Stats
    class CleanupStatsReporterTest < ActiveSupport::TestCase
      def setup
        @output = StringIO.new
        @reporter = CleanupStatsReporter.new(output: @output)
      end

      def teardown
        Mocha::Mockery.instance.teardown
      end

      # Structure Tests

      test "reporter has output attribute" do
        assert_respond_to @reporter, :output
      end

      test "reporter has config attribute" do
        assert_respond_to @reporter, :config
      end

      test "config returns RailsPulse configuration" do
        assert_equal RailsPulse.configuration, @reporter.config
      end

      test "class method report creates instance and calls report" do
        output = StringIO.new
        CleanupStatsReporter.any_instance.expects(:report)

        CleanupStatsReporter.report(output: output)
      end

      # Report Method Tests

      test "report prints configuration section" do
        @reporter.report

        output_text = @output.string

        assert_includes output_text, "Rails Pulse Cleanup Configuration"
        assert_includes output_text, "Cleanup enabled"
        assert_includes output_text, "Retention period"
        assert_includes output_text, "Table limits"
      end

      test "report prints table sizes section" do
        @reporter.report

        output_text = @output.string

        assert_includes output_text, "Current table sizes"
      end

      test "report prints old records when retention period configured" do
        original = RailsPulse.configuration.full_retention_period
        RailsPulse.configuration.full_retention_period = 30.days

        @reporter.report

        output_text = @output.string

        assert_includes output_text, "Records older than"
      ensure
        RailsPulse.configuration.full_retention_period = original
      end

      test "report skips old records when retention period nil" do
        original = RailsPulse.configuration.full_retention_period
        RailsPulse.configuration.full_retention_period = nil

        @reporter.report

        output_text = @output.string

        refute_includes output_text, "Records older than"
      ensure
        RailsPulse.configuration.full_retention_period = original
      end

      # Print Configuration Tests

      test "print_configuration shows archiving_enabled status" do
        @reporter.send(:print_configuration)

        output_text = @output.string

        assert_includes output_text, "Cleanup enabled:"
      end

      test "print_configuration shows retention period" do
        @reporter.send(:print_configuration)

        output_text = @output.string

        assert_includes output_text, "Retention period:"
      end

      test "print_configuration shows table limits" do
        @reporter.send(:print_configuration)

        output_text = @output.string

        assert_includes output_text, "Table limits:"
      end

      # Print Table Sizes Tests

      test "print_table_sizes lists all tables" do
        @reporter.send(:print_table_sizes)

        output_text = @output.string

        assert_includes output_text, "rails_pulse_requests"
        assert_includes output_text, "rails_pulse_operations"
        assert_includes output_text, "rails_pulse_routes"
        assert_includes output_text, "rails_pulse_queries"
      end

      test "print_table_sizes shows record counts" do
        @reporter.send(:print_table_sizes)

        output_text = @output.string

        assert_match /\d+ records/, output_text
      end

      # Print Table Count Tests

      test "print_table_count shows table name and count" do
        @reporter.send(:print_table_count, "rails_pulse_requests", "RailsPulse::Request")

        output_text = @output.string

        assert_includes output_text, "rails_pulse_requests"
        assert_match /\d+ records/, output_text
      end

      test "print_table_count shows OVER LIMIT when count exceeds limit" do
        original = RailsPulse.configuration.max_table_records
        RailsPulse.configuration.max_table_records = { rails_pulse_requests: 1 }

        @reporter.send(:print_table_count, "rails_pulse_requests", "RailsPulse::Request")

        output_text = @output.string
        if RailsPulse::Request.count > 1
          assert_includes output_text, "OVER LIMIT"
        end
      ensure
        RailsPulse.configuration.max_table_records = original
      end

      test "print_table_count handles NameError gracefully" do
        @reporter.send(:print_table_count, "rails_pulse_unknown", "RailsPulse::Unknown")

        output_text = @output.string

        assert_includes output_text, "Model not found"
      end

      test "print_table_count handles general errors" do
        RailsPulse::Request.stubs(:count).raises(StandardError, "Database error")

        @reporter.send(:print_table_count, "rails_pulse_requests", "RailsPulse::Request")

        output_text = @output.string

        assert_includes output_text, "Error"
      end

      # Print Old Records Count Tests

      test "print_old_records_count shows cutoff time" do
        original = RailsPulse.configuration.full_retention_period
        RailsPulse.configuration.full_retention_period = 30.days

        @reporter.send(:print_old_records_count)

        output_text = @output.string

        assert_includes output_text, "Records older than"
      ensure
        RailsPulse.configuration.full_retention_period = original
      end

      test "print_old_records_count queries Request and Operation models" do
        original = RailsPulse.configuration.full_retention_period
        RailsPulse.configuration.full_retention_period = 30.days

        @reporter.send(:print_old_records_count)

        output_text = @output.string

        assert_includes output_text, "rails_pulse_requests:"
        assert_includes output_text, "rails_pulse_operations:"
      ensure
        RailsPulse.configuration.full_retention_period = original
      end

      test "print_old_records_count shows old record counts" do
        original = RailsPulse.configuration.full_retention_period
        RailsPulse.configuration.full_retention_period = 30.days

        @reporter.send(:print_old_records_count)

        output_text = @output.string

        assert_match /\d+ old records/, output_text
      ensure
        RailsPulse.configuration.full_retention_period = original
      end

      test "print_old_records_count handles errors gracefully" do
        original = RailsPulse.configuration.full_retention_period
        RailsPulse.configuration.full_retention_period = 30.days
        RailsPulse::Request.stubs(:where).raises(StandardError, "Query error")

        @reporter.send(:print_old_records_count)

        output_text = @output.string

        assert_includes output_text, "Error calculating old records"
      ensure
        RailsPulse.configuration.full_retention_period = original
      end

      # Table Models Tests

      test "table_models returns hash with correct structure" do
        models = @reporter.send(:table_models)

        assert_kind_of Hash, models
        assert_equal 4, models.length
      end

      test "table_models includes all expected tables" do
        models = @reporter.send(:table_models)

        assert_includes models.keys, "rails_pulse_requests"
        assert_includes models.keys, "rails_pulse_operations"
        assert_includes models.keys, "rails_pulse_routes"
        assert_includes models.keys, "rails_pulse_queries"
      end

      test "table_models maps to correct model names" do
        models = @reporter.send(:table_models)

        assert_equal "RailsPulse::Request", models["rails_pulse_requests"]
        assert_equal "RailsPulse::Operation", models["rails_pulse_operations"]
        assert_equal "RailsPulse::Route", models["rails_pulse_routes"]
        assert_equal "RailsPulse::Query", models["rails_pulse_queries"]
      end

      # Integration Tests

      test "report can be called multiple times safely" do
        @reporter.report
        @reporter.report

        output_text = @output.string
        # Should have printed configuration twice
        assert_match /Rails Pulse Cleanup Configuration.*Rails Pulse Cleanup Configuration/m, output_text
      end

      test "report outputs complete information in order" do
        @reporter.report

        output_text = @output.string
        config_pos = output_text.index("Cleanup Configuration")
        tables_pos = output_text.index("Current table sizes")

        assert_operator config_pos, :<, tables_pos
      end
    end
  end
end
