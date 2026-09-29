require "test_helper"
require "rails_pulse/cli/install"
require "tmpdir"

module RailsPulse
  module CLI
    class InstallTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      def setup
        @tmpdir = Dir.mktmpdir
        @original_home = ENV["HOME"]
        ENV["HOME"] = @tmpdir
      end

      def teardown
        ENV["HOME"] = @original_home
        FileUtils.rm_rf(@tmpdir)
      end

      def run_install(integration = nil, options = {})
        defaults = { "list" => false }
        cmd = Install.new([], defaults.merge(options.transform_keys(&:to_s)))
        capture_io { cmd.perform(integration) }
      end

      # --- --list flag ---

      test "--list outputs all available integrations" do
        out, _err = run_install(nil, list: true)

        assert_includes out, "claude"
        assert_includes out, "agents"
      end

      # --- claude integration ---

      test "install claude writes the skill to ~/.claude/skills/rails-pulse/SKILL.md" do
        run_install("claude")

        dest = File.join(@tmpdir, ".claude", "skills", "rails-pulse", "SKILL.md")

        assert_path_exists dest, "Expected #{dest} to exist"
      end

      test "the installed skill carries Claude Code front matter" do
        run_install("claude")
        skill = File.read(File.join(@tmpdir, ".claude", "skills", "rails-pulse", "SKILL.md"))

        assert_match(/\A---\nname: rails-pulse\ndescription: .+\n---\n/, skill)
      end

      test "install claude confirms destination in output" do
        out, _err = run_install("claude")

        assert_includes out, "skills/rails-pulse/SKILL.md"
      end

      # --- agents integration ---

      test "install agents copies agents.md to current directory" do
        Dir.chdir(@tmpdir) do
          run_install("agents")

          assert_path_exists File.join(@tmpdir, "agents.md"), "Expected agents.md to exist in #{@tmpdir}"
        end
      end

      test "install agents confirms destination in output" do
        Dir.chdir(@tmpdir) do
          out, _err = run_install("agents")

          assert_includes out, "agents.md"
        end
      end

      test "install agents refuses to overwrite an existing agents.md" do
        Dir.chdir(@tmpdir) do
          File.write("agents.md", "mine\n")

          out, _err = capture_io do
            assert_raises(SystemExit) { Install.new([], { "list" => false }).perform("agents") }
          end

          assert_equal "mine\n", File.read("agents.md")
          assert_includes out, "already exists; not overwriting it"
          assert_includes out, "--append"
        end
      end

      # On a case-insensitive filesystem agents.md and AGENTS.md are the same
      # file, so a project's AGENTS.md must block the install everywhere.
      test "install agents refuses when the project has an AGENTS.md" do
        Dir.chdir(@tmpdir) do
          File.write("AGENTS.md", "project instructions\n")

          out, _err = capture_io do
            assert_raises(SystemExit) { Install.new([], { "list" => false }).perform("agents") }
          end

          assert_equal "project instructions\n", File.read("AGENTS.md")
          assert_includes out, "AGENTS.md already exists"
          assert_equal [ "AGENTS.md" ], Dir.children(@tmpdir)
        end
      end

      # --- agents --append ---
      #
      # A project with its own AGENTS.md should not have to paste the section
      # in by hand, and a re-run must not leave two copies of it.

      test "append adds a delimited Rails Pulse section to an existing AGENTS.md" do
        Dir.chdir(@tmpdir) do
          File.write("AGENTS.md", "# Project instructions\n\nDo the thing.\n")

          out, _err = run_install("agents", append: true)
          written = File.read("AGENTS.md")

          assert_includes out, "Appended a Rails Pulse section"
          assert_includes written, "# Project instructions"
          assert_includes written, "Do the thing."
          assert_includes written, "<!-- rails-pulse:start -->"
          assert_includes written, "<!-- rails-pulse:end -->"
          assert_includes written, "Rails Pulse — Agent Integration"
        end
      end

      test "append leaves the project's own instructions untouched" do
        Dir.chdir(@tmpdir) do
          original = "# Project instructions\n\nDo the thing.\n"
          File.write("AGENTS.md", original)
          run_install("agents", append: true)

          assert File.read("AGENTS.md").start_with?(original)
        end
      end

      test "a second append replaces the section rather than duplicating it" do
        Dir.chdir(@tmpdir) do
          File.write("AGENTS.md", "# Project instructions\n")
          run_install("agents", append: true)
          first = File.read("AGENTS.md")

          out, _err = run_install("agents", append: true)
          second = File.read("AGENTS.md")

          assert_includes out, "Updated the Rails Pulse section"
          assert_equal first, second
          assert_equal 1, second.scan("<!-- rails-pulse:start -->").size
        end
      end

      test "append keeps content the project added after the section" do
        Dir.chdir(@tmpdir) do
          File.write("AGENTS.md", "# Project instructions\n")
          run_install("agents", append: true)
          File.write("AGENTS.md", "#{File.read('AGENTS.md')}\n## Our own notes\n")

          run_install("agents", append: true)
          written = File.read("AGENTS.md")

          assert_includes written, "## Our own notes"
          assert_includes written, "# Project instructions"
          assert_equal 1, written.scan("<!-- rails-pulse:start -->").size
        end
      end

      test "append writes the file when no AGENTS.md exists yet" do
        Dir.chdir(@tmpdir) do
          run_install("agents", append: true)

          assert_path_exists File.join(@tmpdir, "agents.md")
        end
      end

      # --- unknown integration ---

      test "unknown integration shows usage hint" do
        out, _err = run_install("unknown")

        assert_includes out, "Usage:"
      end

      test "no integration shows usage hint" do
        out, _err = run_install(nil)

        assert_includes out, "Usage:"
      end
    end
  end
end
