require "test_helper"

module RailsPulse
  module Tasks
    class CleanupTaskRunnerTest < ActiveSupport::TestCase
      def setup
        @output = StringIO.new
        @runner = CleanupTaskRunner.new(output: @output)
        @original_archiving = RailsPulse.configuration.archiving_enabled
      end

      def teardown
        RailsPulse.configuration.archiving_enabled = @original_archiving
        Mocha::Mockery.instance.teardown
      end

      # Structure Tests

      test "runner has output attribute" do
        assert_respond_to @runner, :output
      end

      test "runner has config attribute" do
        assert_respond_to @runner, :config
      end

      test "config returns RailsPulse configuration" do
        assert_equal RailsPulse.configuration, @runner.config
      end

      test "class method run creates instance and calls run" do
        output = StringIO.new
        CleanupTaskRunner.any_instance.expects(:run).returns(true)

        CleanupTaskRunner.run(output: output)
      end

      # Run Method Tests

      test "run prints starting message" do
        RailsPulse.configuration.archiving_enabled = true
        RailsPulse::CleanupService.stubs(:perform).returns({
          time_based: {},
          count_based: {},
          total_deleted: 0
        })

        @runner.run

        assert_includes @output.string, "Starting Rails Pulse data cleanup"
      end

      test "run returns false when archiving disabled" do
        RailsPulse.configuration.archiving_enabled = false

        result = @runner.run

        refute result
      end

      test "run prints disabled message when archiving disabled" do
        RailsPulse.configuration.archiving_enabled = false

        @runner.run

        assert_includes @output.string, "Cleanup is disabled"
      end

      test "run returns true when cleanup succeeds" do
        RailsPulse.configuration.archiving_enabled = true
        RailsPulse::CleanupService.stubs(:perform).returns({
          time_based: {},
          count_based: {},
          total_deleted: 0
        })

        result = @runner.run

        assert result
      end

      test "run calls CleanupService.perform" do
        RailsPulse.configuration.archiving_enabled = true
        RailsPulse::CleanupService.expects(:perform).returns({
          time_based: {},
          count_based: {},
          total_deleted: 0
        })

        @runner.run
      end

      test "run prints completion message" do
        RailsPulse.configuration.archiving_enabled = true
        RailsPulse::CleanupService.stubs(:perform).returns({
          time_based: {},
          count_based: {},
          total_deleted: 0
        })

        @runner.run

        assert_includes @output.string, "Cleanup completed"
      end

      test "run returns false on error" do
        RailsPulse.configuration.archiving_enabled = true
        RailsPulse::CleanupService.stubs(:perform).raises(StandardError, "Test error")

        result = @runner.run

        refute result
      end

      test "run prints error message on failure" do
        RailsPulse.configuration.archiving_enabled = true
        RailsPulse::CleanupService.stubs(:perform).raises(StandardError, "Test error")

        @runner.run

        assert_includes @output.string, "Cleanup failed"
        assert_includes @output.string, "Test error"
      end

      # Print Results Tests

      test "print_results shows total deleted count" do
        stats = {
          time_based: { rails_pulse_requests: 5 },
          count_based: { rails_pulse_operations: 3 },
          total_deleted: 8
        }

        @runner.send(:print_results, stats)

        output_text = @output.string
        assert_includes output_text, "Total: 8"
      end

      test "print_results shows time-based cleanup total" do
        stats = {
          time_based: { rails_pulse_requests: 5, rails_pulse_operations: 3 },
          count_based: {},
          total_deleted: 8
        }

        @runner.send(:print_results, stats)

        output_text = @output.string
        assert_includes output_text, "Time-based cleanup: 8"
      end

      test "print_results shows count-based cleanup total" do
        stats = {
          time_based: {},
          count_based: { rails_pulse_routes: 10 },
          total_deleted: 10
        }

        @runner.send(:print_results, stats)

        output_text = @output.string
        assert_includes output_text, "Count-based cleanup: 10"
      end

      test "print_results shows breakdown when records deleted" do
        stats = {
          time_based: { rails_pulse_requests: 5 },
          count_based: { rails_pulse_operations: 3 },
          total_deleted: 8
        }

        @runner.send(:print_results, stats)

        output_text = @output.string
        assert_includes output_text, "Breakdown by table"
      end

      test "print_results skips breakdown when no records deleted" do
        stats = {
          time_based: {},
          count_based: {},
          total_deleted: 0
        }

        @runner.send(:print_results, stats)

        output_text = @output.string
        refute_includes output_text, "Breakdown by table"
      end

      # Print Breakdown Tests

      test "print_breakdown shows time-based deletions by table" do
        stats = {
          time_based: { rails_pulse_requests: 5, rails_pulse_routes: 3 },
          count_based: {}
        }

        @runner.send(:print_breakdown, stats)

        output_text = @output.string
        assert_includes output_text, "rails_pulse_requests (time-based): 5"
        assert_includes output_text, "rails_pulse_routes (time-based): 3"
      end

      test "print_breakdown shows count-based deletions by table" do
        stats = {
          time_based: {},
          count_based: { rails_pulse_operations: 10, rails_pulse_queries: 7 }
        }

        @runner.send(:print_breakdown, stats)

        output_text = @output.string
        assert_includes output_text, "rails_pulse_operations (count-based): 10"
        assert_includes output_text, "rails_pulse_queries (count-based): 7"
      end

      test "print_breakdown skips tables with zero count" do
        stats = {
          time_based: { rails_pulse_requests: 5, rails_pulse_routes: 0 },
          count_based: { rails_pulse_operations: 0 }
        }

        @runner.send(:print_breakdown, stats)

        output_text = @output.string
        assert_includes output_text, "rails_pulse_requests"
        refute_includes output_text, "rails_pulse_routes"
        refute_includes output_text, "rails_pulse_operations"
      end

      # Handle Error Tests

      test "handle_error prints error message" do
        error = StandardError.new("Something went wrong")

        @runner.send(:handle_error, error)

        output_text = @output.string
        assert_includes output_text, "Cleanup failed"
        assert_includes output_text, "Something went wrong"
      end

      test "handle_error prints backtrace when VERBOSE set" do
        original_verbose = ENV["VERBOSE"]
        ENV["VERBOSE"] = "true"

        error = StandardError.new("Test error")
        error.set_backtrace(["lib/foo.rb:10", "lib/bar.rb:20"])

        @runner.send(:handle_error, error)

        output_text = @output.string
        assert_includes output_text, "lib/foo.rb:10"
        assert_includes output_text, "lib/bar.rb:20"
      ensure
        ENV["VERBOSE"] = original_verbose
      end

      test "handle_error skips backtrace when VERBOSE not set" do
        original_verbose = ENV["VERBOSE"]
        ENV.delete("VERBOSE")

        error = StandardError.new("Test error")
        error.set_backtrace(["lib/foo.rb:10"])

        @runner.send(:handle_error, error)

        output_text = @output.string
        refute_includes output_text, "lib/foo.rb:10"
      ensure
        ENV["VERBOSE"] = original_verbose if original_verbose
      end

      # Integration Tests

      test "run completes full workflow successfully" do
        RailsPulse.configuration.archiving_enabled = true
        stats = {
          time_based: { rails_pulse_requests: 10 },
          count_based: { rails_pulse_operations: 5 },
          total_deleted: 15
        }
        RailsPulse::CleanupService.stubs(:perform).returns(stats)

        result = @runner.run

        assert result
        output_text = @output.string
        assert_includes output_text, "Starting Rails Pulse data cleanup"
        assert_includes output_text, "Cleanup completed"
        assert_includes output_text, "Total: 15"
      end
    end
  end
end
