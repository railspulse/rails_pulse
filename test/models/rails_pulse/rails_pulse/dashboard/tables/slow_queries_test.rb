require "test_helper"

class RailsPulse::Dashboard::Tables::SlowQueriesTest < ActiveSupport::TestCase
  def setup
    @slow_queries = RailsPulse::Dashboard::Tables::SlowQueries.new

    # Create test data
    @query1 = create(:query, normalized_sql: "SELECT * FROM users WHERE id = ?")
    @query2 = create(:query, normalized_sql: "SELECT COUNT(*) FROM orders WHERE created_at > ?")
    @query3 = create(:query, normalized_sql: "UPDATE products SET updated_at = ? WHERE category_id = ?")

    # Create operations for this week
    this_week_start = 1.week.ago.beginning_of_week

    # Query 1: slowest
    create(:operation, query: @query1, duration: 500, occurred_at: this_week_start + 1.day)
    create(:operation, query: @query1, duration: 600, occurred_at: this_week_start + 2.days)

    # Query 2: medium speed
    create(:operation, query: @query2, duration: 200, occurred_at: this_week_start + 1.day)
    create(:operation, query: @query2, duration: 300, occurred_at: this_week_start + 3.days)

    # Query 3: fastest
    create(:operation, query: @query3, duration: 50, occurred_at: this_week_start + 2.days)
    create(:operation, query: @query3, duration: 100, occurred_at: this_week_start + 4.days)
  end

  test "returns table data with correct structure" do
    result = @slow_queries.to_table_data

    assert_kind_of Hash, result
    assert_includes result.keys, :columns
    assert_includes result.keys, :data
  end

  test "returns correct columns definition" do
    result = @slow_queries.to_table_data
    columns = result[:columns]

    assert_equal 4, columns.length
    assert_equal "Query", columns[0][:label]
    assert_equal "Average Time", columns[1][:label]
    assert_equal "Requests", columns[2][:label]
    assert_equal "Last Request", columns[3][:label]

    assert_equal :query_text, columns[0][:field]
    assert_equal :average_time, columns[1][:field]
    assert_equal :request_count, columns[2][:field]
    assert_equal :last_request, columns[3][:field]

    assert_equal :query_link, columns[0][:link_to]
  end

  test "sorts queries by average duration descending" do
    result = @slow_queries.to_table_data
    data = result[:data]

    # Should be sorted slowest first
    average_times = data.map { |row| row[:average_time] }
    assert_equal average_times.sort.reverse, average_times
  end

  test "limits results to 5 queries" do
    # Create 6 additional queries to test limit
    (1..6).each do |i|
      query = create(:query, normalized_sql: "SELECT * FROM table#{i} WHERE id = ?")
      create(:operation, query: query, duration: 10 + i, occurred_at: 1.week.ago.beginning_of_week + 1.day)
    end

    result = @slow_queries.to_table_data
    assert result[:data].length <= 5
  end

  test "truncates long SQL queries" do
    long_sql = "SELECT users.id, users.name, users.email, users.created_at, users.updated_at FROM users JOIN orders ON users.id = orders.user_id WHERE users.active = true AND orders.status = 'completed'"

    # Test the truncation method directly since database queries can be inconsistent in tests
    slow_queries_instance = RailsPulse::Dashboard::Tables::SlowQueries.new
    truncated_text = slow_queries_instance.send(:truncate_query, long_sql)

    assert truncated_text.length <= 83 # 80 chars + "..."
    assert_includes truncated_text, "..."
    assert_equal "SELECT users.id, users.name, users.email, users.created_at, users.updated_at FRO...", truncated_text
  end

  test "formats time ago correctly" do
    # Test the private method through the public interface
    recent_operation = create(:operation, query: @query1, duration: 100, occurred_at: 30.minutes.ago)

    result = @slow_queries.to_table_data

    # Should contain some time format (exact format may vary based on timing)
    last_request_values = result[:data].map { |row| row[:last_request] }
    assert last_request_values.any? { |time| time =~ /\d+[smhd] ago/ }
  end

  test "handles queries with no operations" do
    # Clear all operations
    RailsPulse::Operation.destroy_all

    result = @slow_queries.to_table_data

    assert_equal [], result[:data]
  end

  test "includes correct query links" do
    result = @slow_queries.to_table_data

    result[:data].each do |row|
      assert_includes row[:query_link], "/rails_pulse/queries/"
      assert row[:query_link] =~ /\/rails_pulse\/queries\/\d+$/
    end
  end
end
