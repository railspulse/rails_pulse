require "fileutils"
require_relative "base_command"

module RailsPulse
  module CLI
    class Install < BaseCommand
      AGENT_FILES_DIR = File.expand_path("agent_files", __dir__)

      # Claude Code loads skills from ~/.claude/skills/<name>/SKILL.md; the
      # file carries its own name and description in YAML front matter.
      CLAUDE_SKILL_PATH = "~/.claude/skills/rails-pulse/SKILL.md".freeze

      AGENTS_FILE = "agents.md".freeze

      # Delimit the section so a re-run can replace exactly what a previous
      # run wrote, leaving everything a project put around it untouched.
      SECTION_START = "<!-- rails-pulse:start -->".freeze
      SECTION_END = "<!-- rails-pulse:end -->".freeze
      SECTION_PATTERN = /^#{Regexp.escape(SECTION_START)}\n.*?^#{Regexp.escape(SECTION_END)}\n?/m

      INTEGRATIONS = {
        "claude" => {
          description: "Claude Code skill → #{CLAUDE_SKILL_PATH}",
          source: "claude_skill.md"
        },
        "agents" => {
          description: "Generic agent descriptor → ./#{AGENTS_FILE}",
          source: "agents.md"
        }
      }.freeze

      default_task :perform

      desc "perform [INTEGRATION]", "Install an AI agent integration file"
      long_desc <<~DESC
        Copy a pre-built integration file to the correct location for the given agent framework.

        Available integrations:
          claude   Installs a Claude Code skill to #{CLAUDE_SKILL_PATH}.
                   Claude Code then knows when and how to use the Rails Pulse MCP tools and CLI.
                   An earlier copy of the skill is replaced.
          agents   Installs a generic agent descriptor to ./#{AGENTS_FILE} in the current directory.
                   Compatible with other AI agent frameworks, including Codex. When an agents.md
                   or AGENTS.md already exists it is never overwritten: pass --append to add a
                   delimited Rails Pulse section to the end of it, which a later --append
                   replaces in place rather than duplicating.

        Run --list to see all available integrations.
      DESC
      option :list, type: :boolean, desc: "List all available integrations and their destinations"
      option :append, type: :boolean, default: false,
                      desc: "For 'agents': add a delimited Rails Pulse section to an existing AGENTS.md"
      def perform(integration = nil)
        if options[:list]
          say "Available integrations:"
          INTEGRATIONS.each { |name, meta| say "  #{name.ljust(10)} #{meta[:description]}" }
          return
        end

        case integration
        when "claude"
          install_claude
        when "agents"
          install_agents
        else
          say "Usage: rails-pulse install [claude|agents]", :yellow
          say "       rails-pulse install --list"
        end
      end

      private

      def install_claude
        dest = File.expand_path(CLAUDE_SKILL_PATH)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(File.join(AGENT_FILES_DIR, "claude_skill.md"), dest)
        say "Installed Claude Code skill to #{dest}", :green
      end

      # A project's own AGENTS.md is compared case-insensitively: on a
      # case-insensitive filesystem (macOS by default) writing agents.md
      # would silently replace it.
      def install_agents
        source = File.join(AGENT_FILES_DIR, "agents.md")
        existing = Dir.children(Dir.pwd).find { |name| name.casecmp?(AGENTS_FILE) }

        return append_to_agents(File.join(Dir.pwd, existing), source) if existing && options[:append]

        if existing
          say "#{File.join(Dir.pwd, existing)} already exists; not overwriting it.", :yellow
          say "Run `rails-pulse install agents --append` to add a Rails Pulse section to it instead."
          exit 1
        end

        dest = File.join(Dir.pwd, AGENTS_FILE)
        FileUtils.cp(source, dest)
        say "Installed agent descriptor to #{dest}", :green
      end

      # The project's own instructions are never rewritten: the Rails Pulse
      # section is delimited, so a re-run replaces it where it sits and
      # everything around it is left exactly as the project wrote it.
      def append_to_agents(dest, source)
        existing = File.read(dest)
        section = "#{SECTION_START}\n#{File.read(source).strip}\n#{SECTION_END}\n"

        if existing.match?(SECTION_PATTERN)
          File.write(dest, existing.sub(SECTION_PATTERN, section))
          say "Updated the Rails Pulse section in #{dest}", :green
        else
          separator = existing.end_with?("\n\n") ? "" : (existing.end_with?("\n") ? "\n" : "\n\n")
          File.write(dest, "#{existing}#{separator}#{section}")
          say "Appended a Rails Pulse section to #{dest}", :green
        end
      end
    end
  end
end
