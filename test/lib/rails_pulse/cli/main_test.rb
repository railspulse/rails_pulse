require "test_helper"
require "rails_pulse/cli/main"

module RailsPulse
  module CLI
    class MainTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      # --- help output ---

      test "help with no command outputs examples section" do
        cmd = Main.new([])

        out, _err = capture_io { cmd.help(nil) }

        assert_includes out, "Examples:"
        assert_includes out, "rails-pulse configure"
        assert_includes out, "rails-pulse deployments list"
      end

      test "help with a specific command does not output examples section" do
        cmd = Main.new([])

        out, _err = capture_io { cmd.help("routes") }

        refute_includes out, "Examples:"
      end

      # --- exit status ---
      #
      # A script or CI step can only tell a usage error from success by the
      # exit status.

      test "an unknown command exits 1" do
        _out, err = capture_subprocess_io { system(RbConfig.ruby, "-Ilib", "exe/rails-pulse", "bogus") }

        assert_equal 1, $?.exitstatus
        refute_includes err, "Deprecation warning"
      end

      test "an unknown flag on a subcommand exits 1" do
        _out, err = capture_subprocess_io { system(RbConfig.ruby, "-Ilib", "exe/rails-pulse", "routes", "list", "--nope") }

        assert_equal 1, $?.exitstatus
        assert_includes err, "Unknown switches"
      end

      # --- subcommand registration ---

      test "all expected subcommands are registered" do
        registered = Main.all_tasks.keys

        %w[configure install routes requests queries jobs job_runs exceptions deployments mcp].each do |name|
          assert_includes registered, name, "Expected '#{name}' to be registered"
        end
      end
    end
  end
end
