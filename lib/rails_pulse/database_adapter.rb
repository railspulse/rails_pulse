# frozen_string_literal: true

module RailsPulse
  # Which database a connection talks to, for the SQL that differs between
  # PostgreSQL, MySQL and SQLite.
  #
  # Adapters built on a Rails one report their own adapter_name
  # (activerecord-postgis-adapter says "PostGIS"), so a name that names none
  # of the three falls back to the adapter's class: a PostGIS connection is a
  # PostgreSQLAdapter. The name is read first so a connection whose
  # adapter_name is stubbed is taken at its word.
  module DatabaseAdapter
    NAME_PATTERNS = {
      postgresql: /postgres/,
      mysql: /mysql|trilogy/,
      sqlite: /sqlite/
    }.freeze

    LABELS = { postgresql: "PostgreSQL", mysql: "MySQL", sqlite: "SQLite" }.freeze

    module_function

    # :postgresql, :mysql, :sqlite, or nil for any other database.
    def family(connection)
      name = connection.adapter_name.to_s.downcase
      NAME_PATTERNS.find { |_, pattern| name.match?(pattern) }&.first || family_from_class(connection)
    end

    def postgresql?(connection)
      family(connection) == :postgresql
    end

    def mysql?(connection)
      family(connection) == :mysql
    end

    def sqlite?(connection)
      family(connection) == :sqlite
    end

    def label(connection)
      LABELS.fetch(family(connection)) { connection.adapter_name.to_s }
    end

    # The adapter classes are only defined once their gem is loaded, and a
    # connection can only be an instance of one that is.
    def family_from_class(connection)
      if defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) &&
          connection.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
        :postgresql
      elsif defined?(ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter) &&
          connection.is_a?(ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter)
        :mysql
      elsif defined?(ActiveRecord::ConnectionAdapters::SQLite3Adapter) &&
          connection.is_a?(ActiveRecord::ConnectionAdapters::SQLite3Adapter)
        :sqlite
      end
    end
    private_class_method :family_from_class
  end
end
