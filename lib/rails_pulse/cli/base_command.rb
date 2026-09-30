require "thor"
require_relative "config"
require_relative "client"

module RailsPulse
  module CLI
    class BaseCommand < Thor
      # A usage error (unknown command, missing argument, bad flag) exits 1,
      # so a script or CI step running the CLI can tell it failed.
      def self.exit_on_failure?
        true
      end

      # A mistyped flag is an error rather than silently ignored, so
      # `--limt 5` does not quietly return the default page.
      check_unknown_options!

      no_commands do
        def with_error_handling
          yield
        rescue RailsPulse::CLI::Config::ConfigError => e
          say "Error: #{e.message}.", :red
          exit 1
        rescue RailsPulse::CLI::Client::ApiError => e
          say "API error: #{e.message}", :red
          exit 1
        end
      end

      private

      def client
        @client ||= Client.new
      end
    end
  end
end
