require "support/shared_index_page_test"

class QueriesIndexPageTest < SharedIndexPageTest
  def page_path
    "/queries"
  end

  def page_type
    :queries
  end

  def chart_selector
    "#average_query_times_chart"
  end

  def performance_filter_options
    {
      slow: "Slow (≥ 100ms)",
      critical: "Critical (≥ 1000ms)"
    }
  end

  def all_test_data
    (@fast_queries || []) + (@slow_queries || []) + (@very_slow_queries || []) + (@critical_queries || []) +
    [ @last_week_only_query, @last_month_only_query, @old_query ].compact
  end

  def default_scope_data
    (@fast_queries + @slow_queries + @very_slow_queries + @critical_queries)
  end

  def last_week_data
    default_scope_data + [ @last_week_only_query ].compact
  end

  def last_month_data
    default_scope_data + [ @last_week_only_query, @last_month_only_query ].compact
  end

  def slow_performance_data
    (@slow_queries + @very_slow_queries + @critical_queries + [ @last_week_only_query ]).compact
  end

  def critical_performance_data
    @critical_queries
  end

  def zoomed_data
    (@fast_queries + @slow_queries + @very_slow_queries + @critical_queries)
  end

  def metric_card_selectors
    {
      "#average_query_times" => {
        title_regex: /AVERAGE QUERY TIME/,
        title_message: "Average query time card should have correct title",
        value_regex: /\d+(\.\d+)?\s*ms/,
        value_message: "Average query time should show ms value"
      },
      "#percentile_query_times" => {
        title_regex: /95TH PERCENTILE QUERY TIME/,
        title_message: "95th percentile card should have correct title",
        value_regex: /\d+(\.\d+)?\s*ms/,
        value_message: "95th percentile should show ms value"
      },
      "#execution_rate" => {
        title_regex: /EXECUTION RATE/,
        title_message: "Execution rate card should have correct title",
        value_regex: /\d+(\.\d+)?\s*\/\s*min/,
        value_message: "Execution rate should show per minute value"
      }
    }
  end

  def sortable_columns
    [
      {
        name: "Avg Time",
        index: 3,
        value_extractor: ->(text) { text.gsub(/[^\d.]/, "").to_f }
      },
      {
        name: "Query",
        index: 1,
        value_extractor: ->(text) { text.strip }
      }
    ]
  end

  # Test additional sortable columns specific to queries
  def test_additional_sortable_columns_work
    visit_rails_pulse_path "/queries"

    # Wait for table to load
    assert_selector "table tbody tr", wait: 5

    # Test Executions column sorting
    within("table thead") do
      click_link "Executions"
    end
    assert_selector "table tbody tr", wait: 3

    # Test Total Time column sorting
    within("table thead") do
      click_link "Total Time"
    end
    assert_selector "table tbody tr", wait: 3
  end

  private

  def create_comprehensive_test_data
    # Create queries with predictable performance characteristics
    create_performance_categorized_queries

    # Create operations with specific performance patterns
    create_performance_categorized_operations

    # Create Summary data needed for queries index page
    create_summary_data_for_queries
  end

  def create_performance_categorized_queries
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
    # Fast queries: < 100ms
    @fast_queries.each do |query|
      create_operations_for_query(query, avg_duration: 50, count: 20, time_spread: :recent)
      create_operations_for_query(query, avg_duration: 30, count: 15, time_spread: :last_week)
    end

    # Slow queries: 100-499ms
    @slow_queries.each do |query|
      create_operations_for_query(query, avg_duration: 200, count: 15, time_spread: :recent)
      create_operations_for_query(query, avg_duration: 150, count: 10, time_spread: :last_week)
    end

    # Very slow queries: 500-999ms
    @very_slow_queries.each do |query|
      create_operations_for_query(query, avg_duration: 700, count: 10, time_spread: :recent)
      create_operations_for_query(query, avg_duration: 600, count: 8, time_spread: :last_week)
    end

    # Critical queries: ≥ 1000ms
    @critical_queries.each do |query|
      create_operations_for_query(query, avg_duration: 2000, count: 5, time_spread: :recent)
      create_operations_for_query(query, avg_duration: 1500, count: 3, time_spread: :last_week)
    end

    # Time-specific queries for testing filtering boundaries
    create_operations_for_query(@last_week_only_query, avg_duration: 200, count: 5, time_spread: :last_week_only)
    create_operations_for_query(@last_month_only_query, avg_duration: 80, count: 8, time_spread: :last_month_only)
    create_operations_for_query(@old_query, avg_duration: 800, count: 3, time_spread: :old)
  end

  def create_operations_for_query(query, avg_duration:, count:, time_spread:)
    base_time = case time_spread
    when :recent then 2.hours.ago
    when :last_week then 10.days.ago
    when :last_week_only then 6.days.ago
    when :last_month_only then 20.days.ago
    when :old then 40.days.ago
    else 3.days.ago
    end

    count.times do |i|
      duration_variation = (avg_duration * 0.4 * rand) - (avg_duration * 0.2)
      actual_duration = [ 1, avg_duration + duration_variation ].max.round

      # Create a request first since operation requires one
      unique_path = "/test/query/#{query.id}/#{i}/#{rand(10000)}"
      request = create(:request,
        route: create(:route, path: unique_path, method: "GET"),
        duration: actual_duration,
        occurred_at: base_time + (i * 10).minutes,
        status: rand(10) == 0 ? 500 : 200,
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
    time_spreads = {
      recent: 2.hours.ago,
      last_week: 10.days.ago,
      last_week_only: 6.days.ago,
      last_month_only: 20.days.ago,
      old: 40.days.ago
    }

    time_spreads.each do |spread_type, base_time|
      service = RailsPulse::SummaryService.new("day", base_time.beginning_of_day)
      service.perform

      if spread_type == :recent
        service = RailsPulse::SummaryService.new("hour", base_time.beginning_of_hour)
        service.perform
      end
    end

    service = RailsPulse::SummaryService.new("day", Time.current.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("hour", Time.current.beginning_of_hour)
    service.perform
  end
end
