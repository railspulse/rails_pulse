require "thor"
require_relative "configure"
require_relative "install"
require_relative "routes"
require_relative "requests"
require_relative "queries"
require_relative "jobs"
require_relative "job_runs"
require_relative "exceptions"
require_relative "deployments"
require_relative "coverage"
require_relative "mcp"

module RailsPulse
  module CLI
    class Main < Thor
      def self.exit_on_failure?
        true
      end

      register(Configure, "configure", "configure",
               "Prompt for URL and API token, test the connection, and write ~/.rails-pulse")
      register(Install,   "install",   "install [INTEGRATION]",
               "Install AI agent integration files (claude, agents). Use --list to see options")
      register(Routes,    "routes",    "routes SUBCOMMAND",
               "List tracked HTTP routes and their tags")
      register(Requests,  "requests",  "requests SUBCOMMAND",
               "List recorded HTTP requests with optional status and time filters")
      register(Queries,   "queries",   "queries SUBCOMMAND",
               "List tracked SQL queries and their analysis results")
      register(Jobs,      "jobs",      "jobs SUBCOMMAND",
               "List background jobs with run counts, failure rates, and duration stats")
      register(JobRuns,   "job_runs",  "job_runs SUBCOMMAND",
               "List individual job runs with status, job, and time filters")
      register(Exceptions, "exceptions", "exceptions SUBCOMMAND",
               "List exception groups with status, search, and time filters")
      register(Deployments, "deployments", "deployments SUBCOMMAND",
               "List recorded deployments with optional time filters")
      register(Coverage,  "coverage",  "coverage SUBCOMMAND",
               "What has been recorded, how recently, and any collection gaps")
      register(Mcp,       "mcp",       "mcp",
               "Start MCP server for AI coding agents (Claude Code, Codex, Cursor)")

      no_commands do
        def help(command = nil, subcommand = false)
          super
          return if command

          say ""
          say "Examples:"
          say "  rails-pulse configure                                       # Set up credentials interactively"
          say "  rails-pulse routes list                                     # List all tracked routes"
          say "  rails-pulse requests list --status 5xx --limit 10          # Last 10 server errors"
          say "  rails-pulse requests list --since 2026-06-01T00:00:00Z     # Requests since a timestamp"
          say "  rails-pulse queries list --json                             # Queries with full analysis fields"
          say "  rails-pulse jobs list --status failed                      # Jobs with at least one failure"
          say "  rails-pulse job_runs list --status failed --job ReportJob   # Recent failed runs of one job"
          say "  rails-pulse exceptions list --status open                  # Open exception groups, most recent first"
          say "  rails-pulse exceptions show 42                             # One group with backtraces and params"
          say "  rails-pulse deployments list                                # Recorded deploys, most recent first"
          say "  rails-pulse install claude                                  # Install Claude Code skill file"
          say "  rails-pulse mcp                                             # Start MCP server for AI agents"
          say ""
          say "Credentials are read from RAILS_PULSE_URL / RAILS_PULSE_TOKEN env vars or ~/.rails-pulse."
          say "Run 'rails-pulse configure' to set them up, or 'rails-pulse help COMMAND' for detailed flags."
        end
      end
    end
  end
end
