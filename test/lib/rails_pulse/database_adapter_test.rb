require "test_helper"
require "active_record/connection_adapters/postgresql_adapter"
require "active_record/connection_adapters/abstract_mysql_adapter"
require "active_record/connection_adapters/sqlite3_adapter"

module RailsPulse
  class DatabaseAdapterTest < ActiveSupport::TestCase
    # Adapters that subclass a Rails one under their own name, as
    # activerecord-postgis-adapter does. Allocated, never connected: only the
    # class and adapter_name matter here.
    POSTGIS = Class.new(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) { const_set(:ADAPTER_NAME, "PostGIS") }
    MYSQL_FORK = Class.new(ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter) { const_set(:ADAPTER_NAME, "Vitess") }
    SQLITE_FORK = Class.new(ActiveRecord::ConnectionAdapters::SQLite3Adapter) { const_set(:ADAPTER_NAME, "SpatiaLite") }

    # Structure Tests

    test "family of the test database connection is one of the three supported" do
      assert_includes %i[postgresql mysql sqlite], DatabaseAdapter.family(RailsPulse::ApplicationRecord.connection)
    end

    # Detection Tests

    test "family recognises a PostgreSQL adapter that reports its own name" do
      connection = POSTGIS.allocate

      assert_equal :postgresql, DatabaseAdapter.family(connection)
      assert DatabaseAdapter.postgresql?(connection)
      assert_not DatabaseAdapter.mysql?(connection)
      assert_not DatabaseAdapter.sqlite?(connection)
      assert_equal "PostgreSQL", DatabaseAdapter.label(connection)
    end

    test "family recognises a MySQL adapter that reports its own name" do
      connection = MYSQL_FORK.allocate

      assert_equal :mysql, DatabaseAdapter.family(connection)
      assert_equal "MySQL", DatabaseAdapter.label(connection)
    end

    test "family recognises a SQLite adapter that reports its own name" do
      connection = SQLITE_FORK.allocate

      assert_equal :sqlite, DatabaseAdapter.family(connection)
      assert_equal "SQLite", DatabaseAdapter.label(connection)
    end

    test "family reads the standard adapter names" do
      {
        "PostgreSQL" => :postgresql,
        "Mysql2" => :mysql,
        "Trilogy" => :mysql,
        "SQLite" => :sqlite
      }.each do |name, family|
        assert_equal family, DatabaseAdapter.family(named_connection(name)), name
      end
    end

    # Edge Cases

    test "family is nil for an adapter that is none of the three" do
      connection = named_connection("SQLServer")

      assert_nil DatabaseAdapter.family(connection)
      assert_not DatabaseAdapter.postgresql?(connection)
      assert_equal "SQLServer", DatabaseAdapter.label(connection)
    end

    private

    def named_connection(name)
      Struct.new(:adapter_name).new(name)
    end
  end
end
