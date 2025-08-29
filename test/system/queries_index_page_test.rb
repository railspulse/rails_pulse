require "support/application_system_test_case"

class QueriesIndexPageTest < ApplicationSystemTestCase
  include ChartValidationHelpers
  include TableValidationHelpers

  def setup
    super
    create_comprehensive_test_data
  end

  test "queries index page loads and displays data" do
    visit_rails_pulse_path "/queries"

    # Verify basic page structure
    assert_selector "body"
    assert_selector "table"
    assert_current_path "/rails_pulse/queries"

    # Verify chart container exists
    assert_selector "#average_query_times_chart"
    assert_selector "[data-rails-pulse--index-target='chart']"

    # Verify chart data matches expected test data
    expected_queries = all_test_queries
    validate_chart_data("#average_query_times_chart", expected_data: expected_queries)
    validate_table_data(page_type: :queries, expected_data: expected_queries)

    # Try "Last Month" filter to see all our test queries
    select "Last Month", from: "q[period_start_range]"
    click_button "Search"

    validate_chart_data("#average_query_times_chart", expected_data: expected_queries, filter_applied: "Last Month")
    validate_table_data(page_type: :queries, expected_data: expected_queries, filter_applied: "Last Month")
  end

  test "time range filter updates chart and table data" do
    visit_rails_pulse_path "/queries"

    # Capture initial data - should show recent queries but not last_week_only, last_month_only, or old queries
    default_scope_queries = (@fast_queries + @slow_queries + @very_slow_queries + @critical_queries)
    validate_chart_data("#average_query_times_chart", expected_data: default_scope_queries)
    validate_table_data(page_type: :queries)

    # Test Last Week filter - should include last_week_only query but exclude last_month_only and old queries
    select "Last Week", from: "q[period_start_range]"
    click_button "Search"

    # Verify page updated (may have query parameters)
    assert_current_path "/rails_pulse/queries", ignore_query: true
    last_week_queries = default_scope_queries + [ @last_week_only_query ].compact
    validate_chart_data("#average_query_times_chart", expected_data: last_week_queries, filter_applied: "Last Week")
    validate_table_data(page_type: :queries, filter_applied: "Last Week")

    # Test Last Month filter - should include all except old query
    select "Last Month", from: "q[period_start_range]"
    click_button "Search"

    last_month_queries = default_scope_queries + [ @last_week_only_query, @last_month_only_query ].compact
    validate_chart_data("#average_query_times_chart", expected_data: last_month_queries, filter_applied: "Last Month")
    validate_table_data(page_type: :queries, filter_applied: "Last Month")
  end

  test "performance duration filter works correctly" do
    visit_rails_pulse_path "/queries"

    # Test "Slow" filter - should show queries ≥ 100ms
    select "Slow (≥ 100ms)", from: "q[avg_duration]"
    click_button "Search"

    # Validate slow queries are shown (≥ 100ms average) - should include slow, very_slow, critical, and last_week_only
    slow_queries = (@slow_queries + @very_slow_queries + @critical_queries + [ @last_week_only_query ]).compact
    validate_chart_data("#average_query_times_chart", expected_data: slow_queries, filter_applied: "Slow")
    validate_table_data(page_type: :queries, filter_applied: "Slow")

    # Test "Critical" filter - should show queries ≥ 1000ms (only critical queries)
    # First, switch to "Last Month" to ensure we capture all our test data
    select "Last Month", from: "q[period_start_range]"
    select "Critical (≥ 1000ms)", from: "q[avg_duration]"
    click_button "Search"

    # Validate critical queries are shown (≥ 1000ms average)
    critical_queries = @critical_queries
    validate_chart_data("#average_query_times_chart", expected_data: critical_queries, filter_applied: "Critical")
    validate_table_data(page_type: :queries, filter_applied: "Critical")
  end

  test "combined filters work together" do
    visit_rails_pulse_path "/queries"

    # Test combined filtering: slow queries from last week
    select "Slow (≥ 100ms)", from: "q[avg_duration]"
    select "Last Week", from: "q[period_start_range]"
    click_button "Search"

    # Wait for page to update
    assert_selector "tbody", wait: 5
    sleep 0.5  # Allow DOM to fully stabilize

    # Verify combined filtering results using standard validation
    # Expected: slow queries (≥ 100ms) from last week time range
    expected_combined_queries = (@slow_queries + @very_slow_queries + @critical_queries + [ @last_week_only_query ]).compact
    validate_chart_data("#average_query_times_chart", expected_data: expected_combined_queries, filter_applied: "Combined Slow + Last Week")
    validate_table_data(page_type: :queries, filter_applied: "Slow")
  end

  private

  def all_test_queries
    (@fast_queries || []) + (@slow_queries || []) + (@very_slow_queries || []) + (@critical_queries || []) +
    [ @last_week_only_query, @last_month_only_query, @old_query ].compact
  end

  def create_comprehensive_test_data
    # Create queries with predictable performance characteristics
    create_performance_categorized_queries

    # Create operations with specific performance patterns
    create_performance_categorized_operations

    # Create Summary data needed for queries index page
    create_summary_data_for_queries
  end

  def create_performance_categorized_queries
    # Create queries for each performance threshold with distinctive SQL patterns
    # Query thresholds: fast < 100ms, slow 100-499ms, very_slow 500-999ms, critical ≥ 1000ms
    @fast_queries = [
      create(:query, :select_query, normalized_sql: "SELECT id FROM users WHERE id = ?"),
      create(:query, :select_query, normalized_sql: "SELECT name FROM categories WHERE active = ?"),
      create(:query, :select_query, normalized_sql: "SELECT COUNT(*) FROM sessions WHERE user_id = ?")
    ]

    @slow_queries = [
      create(:query, :complex_query, normalized_sql: "SELECT u.*, p.* FROM users u LEFT JOIN profiles p ON u.id = p.user_id WHERE u.active = ?"),
      create(:query, :select_query, normalized_sql: "SELECT * FROM orders o JOIN users u ON o.user_id = u.id WHERE o.status = ?")
    ]

    @very_slow_queries = [
      create(:query, :complex_query, normalized_sql: "SELECT COUNT(*) FROM posts p JOIN comments c ON p.id = c.post_id GROUP BY p.category_id HAVING COUNT(*) > ?"),
      create(:query, :complex_query, normalized_sql: "SELECT AVG(rating) FROM reviews r JOIN products p ON r.product_id = p.id WHERE p.category IN (?)")
    ]

    @critical_queries = [
      create(:query, :complex_query, normalized_sql: "SELECT * FROM audit_logs WHERE created_at BETWEEN ? AND ? ORDER BY created_at")
    ]

    # Create time-specific queries to test filtering
    @last_week_only_query = create(:query, :slow, normalized_sql: "SELECT * FROM weekly_reports WHERE week = ?")
    @last_month_only_query = create(:query, :fast, normalized_sql: "SELECT * FROM monthly_stats WHERE month = ?")
    @old_query = create(:query, :very_slow, normalized_sql: "SELECT * FROM archived_data WHERE archived_at < ?")
  end

  def create_performance_categorized_operations
    # Create operations with known performance characteristics aligned with query thresholds
    # Fast queries: < 100ms (configured threshold: 100ms)
    @fast_queries.each do |query|
      create_operations_for_query(query, avg_duration: 50, count: 20, time_spread: :recent)
      create_operations_for_query(query, avg_duration: 30, count: 15, time_spread: :last_week)
    end

    # Slow queries: 100-499ms (configured threshold: slow: 100ms, very_slow: 500ms)
    @slow_queries.each do |query|
      create_operations_for_query(query, avg_duration: 200, count: 15, time_spread: :recent)
      create_operations_for_query(query, avg_duration: 150, count: 10, time_spread: :last_week)
    end

    # Very slow queries: 500-999ms (configured threshold: very_slow: 500ms, critical: 1000ms)
    @very_slow_queries.each do |query|
      create_operations_for_query(query, avg_duration: 700, count: 10, time_spread: :recent)
      create_operations_for_query(query, avg_duration: 600, count: 8, time_spread: :last_week)
    end

    # Critical queries: ≥ 1000ms (configured threshold: critical: 1000ms)
    @critical_queries.each do |query|
      create_operations_for_query(query, avg_duration: 2000, count: 5, time_spread: :recent)
      create_operations_for_query(query, avg_duration: 1500, count: 3, time_spread: :last_week)
    end

    # Time-specific queries for testing filtering boundaries
    # Last week only query - should appear in "Last Week" and "Last Month" filters but not default scope
    create_operations_for_query(@last_week_only_query, avg_duration: 200, count: 5, time_spread: :last_week_only)

    # Last month only query - should appear only in "Last Month" filter
    create_operations_for_query(@last_month_only_query, avg_duration: 80, count: 8, time_spread: :last_month_only)

    # Old query - should not appear in any time filter (older than 1 month)
    create_operations_for_query(@old_query, avg_duration: 800, count: 3, time_spread: :old)
  end

  def create_operations_for_query(query, avg_duration:, count:, time_spread:)
    base_time = case time_spread
    when :recent then 2.hours.ago  # Within last 24 hours
    when :last_week then 10.days.ago  # Clearly in "last month" range
    when :last_week_only then 6.days.ago  # Only in last week, not in recent/default scope
    when :last_month_only then 20.days.ago  # Only in last month, not in last week
    when :old then 40.days.ago  # Older than any filter scope
    else 3.days.ago
    end

    count.times do |i|
      # Add some variation around the average duration (±20%)
      duration_variation = (avg_duration * 0.4 * rand) - (avg_duration * 0.2)
      actual_duration = [ 1, avg_duration + duration_variation ].max.round

      # Create a request first since operation requires one
      unique_path = "/test/query/#{query.id}/#{i}/#{rand(10000)}"
      request = create(:request,
        route: create(:route, path: unique_path, method: "GET"),
        duration: actual_duration,
        occurred_at: base_time + (i * 10).minutes,
        status: rand(10) == 0 ? 500 : 200, # 10% error rate
        is_error: rand(10) == 0
      )

      create(:operation,
        request: request,
        query: query,
        duration: actual_duration,
        occurred_at: base_time + (i * 10).minutes,
        operation_type: "sql",
        label: query.normalized_sql
      )
    end
  end

  def create_summary_data_for_queries
    # The SummaryService aggregates Operations into Summary records by time periods
    # We need to create summaries that cover the exact time periods where our Operations exist
    
    # Get the actual time ranges where our Operations were created
    time_spreads = {
      recent: 2.hours.ago,
      last_week: 10.days.ago, 
      last_week_only: 6.days.ago,
      last_month_only: 20.days.ago,
      old: 40.days.ago
    }
    
    time_spreads.each do |spread_type, base_time|
      # For each time spread, create summaries that cover the full range
      # where operations might exist (base_time to base_time + operations*10.minutes)
      
      # Create daily summaries for the day containing each time spread
      service = RailsPulse::SummaryService.new("day", base_time.beginning_of_day)
      service.perform
      
      # For recent data, also create hourly summaries for more granular data
      if spread_type == :recent
        service = RailsPulse::SummaryService.new("hour", base_time.beginning_of_hour)
        service.perform
      end
    end
    
    # Also create a summary for "today" to ensure default view has data
    service = RailsPulse::SummaryService.new("day", Time.current.beginning_of_day)
    service.perform
    
    service = RailsPulse::SummaryService.new("hour", Time.current.beginning_of_hour)
    service.perform
  end
end
