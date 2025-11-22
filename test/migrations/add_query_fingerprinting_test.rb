require "test_helper"

class AddQueryFingerprintingTest < ActiveSupport::TestCase
  def setup
    @migration = AddQueryFingerprinting.new
    @connection = ActiveRecord::Base.connection
  end

  def teardown
    # Ensure we're in a clean state after each test
    if @connection.column_exists?(:rails_pulse_queries, :hashed_sql)
      @connection.remove_column :rails_pulse_queries, :hashed_sql if @connection.column_exists?(:rails_pulse_queries, :hashed_sql)
    end

    # Restore normalized_sql to text if needed
    unless @connection.columns(:rails_pulse_queries).find { |c| c.name == "normalized_sql" }&.type == :text
      @connection.change_column :rails_pulse_queries, :normalized_sql, :text
    end
  end

  test "adds hashed_sql column" do
    # Ensure column doesn't exist
    @connection.remove_column :rails_pulse_queries, :hashed_sql if @connection.column_exists?(:rails_pulse_queries, :hashed_sql)

    @migration.up

    assert @connection.column_exists?(:rails_pulse_queries, :hashed_sql), "hashed_sql column should exist"
    column = @connection.columns(:rails_pulse_queries).find { |c| c.name == "hashed_sql" }

    assert_equal :string, column.type
    assert_equal 32, column.limit
    refute column.null, "hashed_sql should be NOT NULL"
  end

  test "creates unique index on hashed_sql" do
    # Ensure column doesn't exist
    @connection.remove_column :rails_pulse_queries, :hashed_sql if @connection.column_exists?(:rails_pulse_queries, :hashed_sql)

    @migration.up

    assert @connection.index_exists?(:rails_pulse_queries, :hashed_sql, unique: true),
           "Unique index on hashed_sql should exist"
  end

  test "removes old normalized_sql index" do
    # Ensure column doesn't exist
    @connection.remove_column :rails_pulse_queries, :hashed_sql if @connection.column_exists?(:rails_pulse_queries, :hashed_sql)

    # Add the old index if it doesn't exist
    unless @connection.index_exists?(:rails_pulse_queries, name: "index_rails_pulse_queries_on_normalized_sql")
      @connection.add_index :rails_pulse_queries, :normalized_sql, unique: true,
                           name: "index_rails_pulse_queries_on_normalized_sql", length: 191
    end

    @migration.up

    refute @connection.index_exists?(:rails_pulse_queries, name: "index_rails_pulse_queries_on_normalized_sql"),
           "Old normalized_sql index should be removed"
  end

  test "changes normalized_sql to text type" do
    # Ensure column doesn't exist
    @connection.remove_column :rails_pulse_queries, :hashed_sql if @connection.column_exists?(:rails_pulse_queries, :hashed_sql)

    # Ensure normalized_sql is varchar first
    @connection.change_column :rails_pulse_queries, :normalized_sql, :string, limit: 1000

    @migration.up

    column = @connection.columns(:rails_pulse_queries).find { |c| c.name == "normalized_sql" }

    assert_equal :text, column.type, "normalized_sql should be text type"
  end

  test "backfills hashed_sql for existing queries" do
    # Ensure column doesn't exist
    @connection.remove_column :rails_pulse_queries, :hashed_sql if @connection.column_exists?(:rails_pulse_queries, :hashed_sql)

    # Create test queries
    query1 = RailsPulse::Query.create!(normalized_sql: "SELECT * FROM users WHERE id = ?")
    query2 = RailsPulse::Query.create!(normalized_sql: "SELECT * FROM posts WHERE user_id = ?")

    @migration.up

    query1.reload
    query2.reload

    assert_not_nil query1.hashed_sql, "query1 should have hashed_sql"
    assert_not_nil query2.hashed_sql, "query2 should have hashed_sql"
    assert_equal Digest::MD5.hexdigest(query1.normalized_sql), query1.hashed_sql
    assert_equal Digest::MD5.hexdigest(query2.normalized_sql), query2.hashed_sql
  end

  test "merges duplicate queries with same normalized_sql" do
    # Ensure column doesn't exist
    @connection.remove_column :rails_pulse_queries, :hashed_sql if @connection.column_exists?(:rails_pulse_queries, :hashed_sql)

    # Create duplicate queries (same normalized SQL)
    sql = "SELECT * FROM users WHERE id = ?"
    query1 = RailsPulse::Query.create!(normalized_sql: sql)
    query2 = RailsPulse::Query.create!(normalized_sql: sql)

    # Create operations for both queries
    route = RailsPulse::Route.create!(method: "GET", path: "/test")
    request = RailsPulse::Request.create!(
      route: route,
      duration: 100,
      status: 200,
      request_uuid: SecureRandom.uuid,
      occurred_at: Time.current
    )

    op1 = RailsPulse::Operation.create!(
      query: query1,
      request: request,
      operation_type: "sql",
      label: sql,
      duration: 10,
      occurred_at: Time.current
    )
    op2 = RailsPulse::Operation.create!(
      query: query2,
      request: request,
      operation_type: "sql",
      label: sql,
      duration: 20,
      occurred_at: Time.current
    )

    @migration.up

    # One query should remain
    assert_equal 1, RailsPulse::Query.where(normalized_sql: sql).count,
                 "Duplicate queries should be merged into one"

    # Both operations should point to the same query
    op1.reload
    op2.reload

    assert_equal op1.query_id, op2.query_id, "Both operations should reference the same query"

    # The kept query should have the correct hash
    kept_query = RailsPulse::Query.find_by(normalized_sql: sql)

    assert_equal Digest::MD5.hexdigest(sql), kept_query.hashed_sql
  end

  test "is idempotent - can run multiple times safely" do
    @migration.up
    assert_nothing_raised do
      @migration.up
    end
  end

  test "rollback prevents data loss when long queries exist" do
    @migration.up

    # Create a query longer than 1000 characters
    long_sql = "SELECT * FROM users WHERE name IN (#{"'user', " * 200}'final_user')"
    RailsPulse::Query.create!(normalized_sql: long_sql)

    error = assert_raises(ActiveRecord::IrreversibleMigration) do
      @migration.down
    end

    assert_match(/cannot rollback/i, error.message)
    assert_match(/1000 characters/i, error.message)
  end

  test "rollback succeeds when no long queries exist" do
    @migration.up

    # Create only short queries
    RailsPulse::Query.create!(normalized_sql: "SELECT * FROM users WHERE id = ?")

    assert_nothing_raised do
      @migration.down
    end

    refute @connection.column_exists?(:rails_pulse_queries, :hashed_sql),
           "hashed_sql column should be removed after rollback"

    assert @connection.index_exists?(:rails_pulse_queries, name: "index_rails_pulse_queries_on_normalized_sql"),
           "Old normalized_sql index should be restored"

    column = @connection.columns(:rails_pulse_queries).find { |c| c.name == "normalized_sql" }

    assert_equal :string, column.type, "normalized_sql should be back to string type"
    assert_equal 1000, column.limit, "normalized_sql should have 1000 char limit"
  end
end
