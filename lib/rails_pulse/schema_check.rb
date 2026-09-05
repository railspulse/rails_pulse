# frozen_string_literal: true

require "generators/rails_pulse/schema_parser"

module RailsPulse
  # Compares the live Rails Pulse tables with the schema this gem version
  # ships (db/rails_pulse_schema.rb) and answers one question: can this
  # process safely read and write them?
  #
  # The answer is "no" exactly when new gem code is running against tables
  # that predate it — a deploy that shipped the gem before `db:migrate`, or a
  # rolling restart that left old and new processes side by side. Without
  # this guard that state surfaces as a "Failed to persist tracking data"
  # log line on every request and a 500 on every dashboard page. With it,
  # tracking pauses after one warning and the dashboard explains what to run.
  #
  # The comparison is by presence only (tables and column names, never
  # types), it runs at most once per process, and any database error is
  # treated as "not outdated" so a booting app without a database (assets
  # precompile, db:create) is never blocked.
  module SchemaCheck
    UPGRADE_INSTRUCTIONS = [
      "rails generate rails_pulse:upgrade",
      "rails db:migrate                  # separate Pulse database: rails db:migrate:rails_pulse",
      "rails rails_pulse:migrate_routes  # once, after the route identity migrations"
    ].freeze

    class << self
      def current?
        missing.empty?
      end

      # { "rails_pulse_routes" => ["http_methods", "controller_action"] }
      # for a table missing columns, { "rails_pulse_exception_groups" => [:table] }
      # for a table that does not exist at all. Empty when everything is present.
      def missing
        cached = @missing
        return cached if cached

        result = compute_missing
        # Only remember a completed comparison; a database error is retried
        # on the next call rather than cached as either answer.
        @missing = result unless result.nil?
        result || {}
      end

      # Tracking entry points call this instead of writing straight away. The
      # first refusal logs the upgrade instructions; later ones are silent.
      def tracking_allowed?
        return true if current?

        warn_once!
        false
      end

      def warn_once!
        return if @warned

        @warned = true
        RailsPulse.logger.error(warning_message)
      end

      def warning_message
        lines = missing.map do |table, columns|
          columns == [ :table ] ? "  #{table} (table missing)" : "  #{table}: #{columns.join(', ')}"
        end
        <<~MESSAGE.chomp
          Rails Pulse #{RailsPulse::VERSION} is running against a database that has not been migrated for it.
          Tracking is paused and the dashboard is unavailable until the schema is upgraded. Missing:
          #{lines.join("\n")}
          To upgrade:
          #{UPGRADE_INSTRUCTIONS.map { |line| "  #{line}" }.join("\n")}
        MESSAGE
      end

      # The gem's own schema file is the reference, not the host's copy:
      # a host that skipped `rails generate rails_pulse:upgrade` has a stale
      # copy that would match its stale tables.
      def expected_schema
        @expected_schema ||= RailsPulse::Generators::SchemaParser.new(schema_path).extract_expected_schema
      end

      def reset!
        @missing = nil
        @warned = nil
        @expected_schema = nil
      end

      private

      def schema_path
        RailsPulse::Engine.root.join("db", "rails_pulse_schema.rb").to_s
      end

      def compute_missing
        connection = RailsPulse::ApplicationRecord.connection
        expected_schema.each_with_object({}) do |(table, columns), missing|
          unless connection.table_exists?(table)
            missing[table] = [ :table ]
            next
          end

          absent = columns.keys - connection.columns(table).map(&:name)
          missing[table] = absent if absent.any?
        end
      rescue ActiveRecord::ActiveRecordError, PG::Error, SQLite3::Exception, Mysql2::Error
        nil
      rescue NameError => e
        # An adapter constant above is not loaded when that adapter isn't in use.
        raise unless e.name.to_s.match?(/\A(PG|SQLite3|Mysql2)\z/)
        retry_without_adapter_constants
      end

      def retry_without_adapter_constants
        connection = RailsPulse::ApplicationRecord.connection
        expected_schema.each_with_object({}) do |(table, columns), missing|
          unless connection.table_exists?(table)
            missing[table] = [ :table ]
            next
          end

          absent = columns.keys - connection.columns(table).map(&:name)
          missing[table] = absent if absent.any?
        end
      rescue StandardError
        nil
      end
    end
  end
end
