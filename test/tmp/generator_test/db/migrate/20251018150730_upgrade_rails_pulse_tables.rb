# Upgrade Rails Pulse tables with new features
class UpgradeRailsPulseTables < ActiveRecord::Migration[8.0]
  def change
    # Add normalized_sql column to rails_pulse_queries
    add_column :rails_pulse_queries, :normalized_sql, :string, comment: "Normalized SQL query string (e.g., SELECT * FROM users WHERE id = ?)"

    # Add analyzed_at column to rails_pulse_queries
    add_column :rails_pulse_queries, :analyzed_at, :datetime, comment: "When query analysis was last performed"

    # Add explain_plan column to rails_pulse_queries
    add_column :rails_pulse_queries, :explain_plan, :text, comment: "EXPLAIN output from actual SQL execution"

    # Add issues column to rails_pulse_queries
    add_column :rails_pulse_queries, :issues, :text, comment: "JSON array of detected performance issues"

    # Add metadata column to rails_pulse_queries
    add_column :rails_pulse_queries, :metadata, :text, comment: "JSON object containing query complexity metrics"

    # Add query_stats column to rails_pulse_queries
    add_column :rails_pulse_queries, :query_stats, :text, comment: "JSON object with query characteristics analysis"

    # Add backtrace_analysis column to rails_pulse_queries
    add_column :rails_pulse_queries, :backtrace_analysis, :text, comment: "JSON object with call chain and N+1 detection"

    # Add index_recommendations column to rails_pulse_queries
    add_column :rails_pulse_queries, :index_recommendations, :text, comment: "JSON array of database index recommendations"

    # Add n_plus_one_analysis column to rails_pulse_queries
    add_column :rails_pulse_queries, :n_plus_one_analysis, :text, comment: "JSON object with enhanced N+1 query detection results"

    # Add suggestions column to rails_pulse_queries
    add_column :rails_pulse_queries, :suggestions, :text, comment: "JSON array of optimization recommendations"



    # Add duration column to rails_pulse_requests
    add_column :rails_pulse_requests, :duration, :decimal, comment: "Total request duration in milliseconds"

    # Add status column to rails_pulse_requests
    add_column :rails_pulse_requests, :status, :integer, comment: "HTTP status code (e.g., 200, 500)"

    # Add is_error column to rails_pulse_requests
    add_column :rails_pulse_requests, :is_error, :boolean, comment: "True if status >= 500"

    # Add request_uuid column to rails_pulse_requests
    add_column :rails_pulse_requests, :request_uuid, :string, comment: "Unique identifier for the request (e.g., UUID)"

    # Add controller_action column to rails_pulse_requests
    add_column :rails_pulse_requests, :controller_action, :string, comment: "Controller and action handling the request (e.g., PostsController#show)"

    # Add occurred_at column to rails_pulse_requests
    add_column :rails_pulse_requests, :occurred_at, :timestamp, comment: "When the request started"



    # Add operation_type column to rails_pulse_operations
    add_column :rails_pulse_operations, :operation_type, :string, comment: "Type of operation (e.g., database, view, gem_call)"

    # Add label column to rails_pulse_operations
    add_column :rails_pulse_operations, :label, :string, comment: "Descriptive name (e.g., SELECT FROM users WHERE id = 1, render layout)"

    # Add duration column to rails_pulse_operations
    add_column :rails_pulse_operations, :duration, :decimal, comment: "Operation duration in milliseconds"

    # Add codebase_location column to rails_pulse_operations
    add_column :rails_pulse_operations, :codebase_location, :string, comment: "File and line number (e.g., app/models/user.rb:25)"

    # Add start_time column to rails_pulse_operations
    add_column :rails_pulse_operations, :start_time, :float, comment: "Operation start time in milliseconds"

    # Add occurred_at column to rails_pulse_operations
    add_column :rails_pulse_operations, :occurred_at, :timestamp, comment: "When the request started"



    # Add period_start column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :period_start, :datetime, comment: "Start of the aggregation period"

    # Add period_end column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :period_end, :datetime, comment: "End of the aggregation period"

    # Add period_type column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :period_type, :string, comment: "Aggregation period type: hour, day, week, month"

    # Add count column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :count, :integer, comment: "Total number of requests/operations"

    # Add avg_duration column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :avg_duration, :float, comment: "Average duration in milliseconds"

    # Add min_duration column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :min_duration, :float, comment: "Minimum duration in milliseconds"

    # Add max_duration column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :max_duration, :float, comment: "Maximum duration in milliseconds"

    # Add p50_duration column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :p50_duration, :float, comment: "50th percentile duration"

    # Add p95_duration column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :p95_duration, :float, comment: "95th percentile duration"

    # Add p99_duration column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :p99_duration, :float, comment: "99th percentile duration"

    # Add total_duration column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :total_duration, :float, comment: "Total duration in milliseconds"

    # Add stddev_duration column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :stddev_duration, :float, comment: "Standard deviation of duration"

    # Add error_count column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :error_count, :integer, comment: "Number of error responses (5xx)"

    # Add success_count column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :success_count, :integer, comment: "Number of successful responses"

    # Add status_2xx column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :status_2xx, :integer, comment: "Number of 2xx responses"

    # Add status_3xx column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :status_3xx, :integer, comment: "Number of 3xx responses"

    # Add status_4xx column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :status_4xx, :integer, comment: "Number of 4xx responses"

    # Add status_5xx column to rails_pulse_summaries
    add_column :rails_pulse_summaries, :status_5xx, :integer, comment: "Number of 5xx responses"
  end

  def down
    remove_column :rails_pulse_queries, :normalized_sql

    remove_column :rails_pulse_queries, :analyzed_at

    remove_column :rails_pulse_queries, :explain_plan

    remove_column :rails_pulse_queries, :issues

    remove_column :rails_pulse_queries, :metadata

    remove_column :rails_pulse_queries, :query_stats

    remove_column :rails_pulse_queries, :backtrace_analysis

    remove_column :rails_pulse_queries, :index_recommendations

    remove_column :rails_pulse_queries, :n_plus_one_analysis

    remove_column :rails_pulse_queries, :suggestions



    remove_column :rails_pulse_requests, :duration

    remove_column :rails_pulse_requests, :status

    remove_column :rails_pulse_requests, :is_error

    remove_column :rails_pulse_requests, :request_uuid

    remove_column :rails_pulse_requests, :controller_action

    remove_column :rails_pulse_requests, :occurred_at



    remove_column :rails_pulse_operations, :operation_type

    remove_column :rails_pulse_operations, :label

    remove_column :rails_pulse_operations, :duration

    remove_column :rails_pulse_operations, :codebase_location

    remove_column :rails_pulse_operations, :start_time

    remove_column :rails_pulse_operations, :occurred_at



    remove_column :rails_pulse_summaries, :period_start

    remove_column :rails_pulse_summaries, :period_end

    remove_column :rails_pulse_summaries, :period_type

    remove_column :rails_pulse_summaries, :count

    remove_column :rails_pulse_summaries, :avg_duration

    remove_column :rails_pulse_summaries, :min_duration

    remove_column :rails_pulse_summaries, :max_duration

    remove_column :rails_pulse_summaries, :p50_duration

    remove_column :rails_pulse_summaries, :p95_duration

    remove_column :rails_pulse_summaries, :p99_duration

    remove_column :rails_pulse_summaries, :total_duration

    remove_column :rails_pulse_summaries, :stddev_duration

    remove_column :rails_pulse_summaries, :error_count

    remove_column :rails_pulse_summaries, :success_count

    remove_column :rails_pulse_summaries, :status_2xx

    remove_column :rails_pulse_summaries, :status_3xx

    remove_column :rails_pulse_summaries, :status_4xx

    remove_column :rails_pulse_summaries, :status_5xx
  end
end
