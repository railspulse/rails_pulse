require "test_helper"

module RailsPulse
  class RouteIndexesTest < ActiveSupport::TestCase
    # Structure Tests

    test "null-action unique index exists" do
      assert RouteIndexes.exists?(Route.connection)
    end

    test "null-action unique index is partial on sqlite and postgresql" do
      skip if mysql?

      index = null_action_index

      assert index.unique
      assert_match(/controller_action IS NULL/i, index.where.to_s)
    end

    test "schema dump keeps the null-action WHERE predicate" do
      skip if mysql?

      dump = schema_dump

      # SQLite dumps `where: "controller_action IS NULL"`; PostgreSQL wraps it
      # in parentheses: `where: "(controller_action IS NULL)"`.
      assert_match(
        /#{Regexp.escape(RouteIndexes::NULL_ACTION_INDEX)}.*, where: ["']\(?controller_action IS NULL\)?["']/,
        dump
      )
    end

    # Edge Cases

    test "paths with an action are not unique-constrained by the null-action index" do
      path = "/shared-index-#{SecureRandom.hex(4)}"

      Route.create!(http_methods: '["GET"]', path: path, controller_action: "home#index", tags: "[]")
      Route.create!(http_methods: '["POST"]', path: path, controller_action: "home#create", tags: "[]")
      Route.create!(http_methods: '["GET"]', path: path, controller_action: nil, tags: "[]")

      assert_equal 3, Route.where(path: path).count
    end

    # Adapter-divergent behavior (mock connection — no real DDL)

    test "ensure is a no-op when the index already exists" do
      conn = mock_connection(adapter: "sqlite3", index_present: true)
      conn.expects(:add_index).never

      RouteIndexes.ensure_null_action_uniqueness!(conn)
    end

    test "ensure adds a partial unique index on non-mysql adapters" do
      conn = mock_connection(adapter: "sqlite3", index_present: false)
      conn.expects(:add_index).with(
        :rails_pulse_routes, :path,
        unique: true,
        where: "controller_action IS NULL",
        name: RouteIndexes::NULL_ACTION_INDEX
      )

      RouteIndexes.ensure_null_action_uniqueness!(conn)
    end

    test "ensure rejects MariaDB" do
      conn = mock_connection(adapter: "mysql2", index_present: false, version: "10.6.7-MariaDB-log")

      error = assert_raises(RuntimeError) { RouteIndexes.ensure_null_action_uniqueness!(conn) }
      assert_match(/MariaDB is not supported/, error.message)
    end

    test "ensure rejects MySQL older than 8.0.13" do
      conn = mock_connection(adapter: "mysql2", index_present: false, version: "5.7.40")

      error = assert_raises(RuntimeError) { RouteIndexes.ensure_null_action_uniqueness!(conn) }
      assert_match(/requires MySQL >= 8.0.13/, error.message)
    end

    test "ensure creates a functional unique index on MySQL 8" do
      conn = mock_connection(adapter: "mysql2", index_present: false, version: "8.0.33")
      conn.stubs(:quote_table_name).with(:rails_pulse_routes).returns("`rails_pulse_routes`")
      conn.expects(:execute).with(regexp_matches(/CREATE UNIQUE INDEX #{RouteIndexes::NULL_ACTION_INDEX}/))

      RouteIndexes.ensure_null_action_uniqueness!(conn)
    end

    test "remove removes the index when present" do
      conn = mock_connection(adapter: "sqlite3", index_present: true)
      conn.expects(:remove_index).with(:rails_pulse_routes, name: RouteIndexes::NULL_ACTION_INDEX)

      RouteIndexes.remove_null_action_uniqueness!(conn)
    end

    test "remove is a no-op when the index is absent" do
      conn = mock_connection(adapter: "sqlite3", index_present: false)
      conn.expects(:remove_index).never

      RouteIndexes.remove_null_action_uniqueness!(conn)
    end

    private

    def null_action_index
      Route.connection.indexes(:rails_pulse_routes).find { |idx| idx.name == RouteIndexes::NULL_ACTION_INDEX }
    end

    def mysql?
      Route.connection.adapter_name.downcase.include?("mysql")
    end

    def schema_dump
      io = StringIO.new
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)
      io.string
    end

    def mock_connection(adapter:, index_present:, version: nil)
      index = Struct.new(:name).new(RouteIndexes::NULL_ACTION_INDEX)
      conn = mock("connection")
      conn.stubs(:adapter_name).returns(adapter)
      conn.stubs(:indexes).with(:rails_pulse_routes).returns(index_present ? [ index ] : [])
      conn.stubs(:select_value).with("SELECT VERSION()").returns(version) if version
      conn
    end
  end
end
