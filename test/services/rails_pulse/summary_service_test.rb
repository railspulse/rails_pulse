require "test_helper"

module RailsPulse
  class SummaryServiceTest < ActiveSupport::TestCase
    # TODO: Test that initialize normalizes period_start using Summary.normalize_period_start
    # TODO: Test that initialize calculates period_end using Summary.calculate_period_end
    # TODO: Test that perform aggregates requests, routes, and queries in a transaction
    # TODO: Test aggregate_requests creates summary with summarizable_id = 0 for overall metrics
    # TODO: Test aggregate_requests calculates avg, min, max, total, p50, p95, p99 durations correctly
    # TODO: Test aggregate_requests counts status codes by category (2xx, 3xx, 4xx, 5xx)
    # TODO: Test aggregate_requests calculates error_count and success_count correctly
    # TODO: Test aggregate_requests calculates standard deviation correctly
    # TODO: Test aggregate_routes creates individual summaries for each route
    # TODO: Test aggregate_routes calculates percentiles and stats per route
    # TODO: Test aggregate_queries creates summaries for each query from operations
    # TODO: Test calculate_percentile returns correct percentile values
    # TODO: Test calculate_percentile returns nil for empty array
    # TODO: Test calculate_stddev returns correct standard deviation
    # TODO: Test calculate_stddev returns nil for empty or single-value arrays
    # TODO: Test that summaries are created or updated (upsert behavior)
    # TODO: Test error handling and logging when perform fails
  end
end
