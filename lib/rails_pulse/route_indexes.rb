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
  # Built with SQL rather than `add_index(..., where:)` so MySQL cannot silently
  # ignore the predicate and unique-index every path.
  module RouteIndexes
    NULL_ACTION_INDEX = "index_rails_pulse_routes_on_path_without_action"

    def self.ensure_null_action_uniqueness!(connection)
      return if exists?(connection)

      table = connection.quote_table_name(:rails_pulse_routes)
      adapter = connection.adapter_name.downcase

      sql = if adapter.include?("mysql")
        <<~SQL
          CREATE UNIQUE INDEX #{NULL_ACTION_INDEX}
          ON #{table} ((CASE WHEN controller_action IS NULL THEN path ELSE NULL END))
        SQL
      else
        <<~SQL
          CREATE UNIQUE INDEX #{NULL_ACTION_INDEX}
          ON #{table} (path)
          WHERE controller_action IS NULL
        SQL
      end

      connection.execute(sql)
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
