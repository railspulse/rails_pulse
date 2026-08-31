# frozen_string_literal: true

module RailsPulse
  # Adapter-specific unique index that groups unrecognized routes (404s, middleware
  # short-circuits) by path. PostgreSQL and SQLite use a partial unique index;
  # MySQL uses a functional unique index because it has no partial indexes.
  #
  # Must not be added while upgrade rows still have a null controller_action on
  # different-verb REST siblings (GET /users vs POST /users). Call this after
  # RouteControllerActionBackfiller has assigned actions.
  #
  # PostgreSQL and SQLite go through `add_index(..., where:)` so `schema.rb`
  # round-trips the predicate. Raw multiline `CREATE UNIQUE INDEX ... WHERE`
  # is stored with a trailing newline that SQLite's schema dumper does not
  # parse, so `db:schema:load` (and parallel test workers) recreate a unique
  # index on every path. MySQL still uses SQL: `add_index(..., where:)` is
  # silently ignored and would unique-index every path.
  module RouteIndexes
    NULL_ACTION_INDEX = "index_rails_pulse_routes_on_path_without_action"

    def self.ensure_null_action_uniqueness!(connection)
      return if exists?(connection)

      adapter = connection.adapter_name.downcase

      if adapter.include?("mysql")
        version_string = connection.select_value("SELECT VERSION()")
        if version_string.to_s.include?("MariaDB")
          raise "Rails Pulse requires MySQL >= 8.0.13 for functional indexes. " \
                "MariaDB is not supported — it does not implement the required " \
                "CREATE INDEX ... ((expression)) syntax."
        end

        mysql_version = version_string.to_s.scan(/\A(\d+\.\d+\.\d+)/).flatten.first
        if mysql_version && Gem::Version.new(mysql_version) < Gem::Version.new("8.0.13")
          raise "Rails Pulse requires MySQL >= 8.0.13 for functional indexes " \
                "(found #{mysql_version}). Upgrade MySQL or use PostgreSQL/SQLite."
        end

        table = connection.quote_table_name(:rails_pulse_routes)
        connection.execute(<<~SQL.strip)
          CREATE UNIQUE INDEX #{NULL_ACTION_INDEX}
          ON #{table} ((CASE WHEN controller_action IS NULL THEN path ELSE NULL END))
        SQL
      else
        connection.add_index(
          :rails_pulse_routes,
          :path,
          unique: true,
          where: "controller_action IS NULL",
          name: NULL_ACTION_INDEX
        )
      end
    end

    def self.remove_null_action_uniqueness!(connection)
      return unless exists?(connection)

      connection.remove_index(:rails_pulse_routes, name: NULL_ACTION_INDEX)
    end

    def self.exists?(connection)
      connection.indexes(:rails_pulse_routes).any? { |idx| idx.name == NULL_ACTION_INDEX }
    end
  end
end
