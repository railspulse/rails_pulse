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
  end
end
