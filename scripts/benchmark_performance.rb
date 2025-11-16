#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive performance benchmark script for Rails Pulse
# This script measures the real-world impact of Rails Pulse on a Rails application

require "bundler/setup"
require "benchmark"
require "benchmark/ips"
require "memory_profiler"

# Load Rails environment
require_relative "../test/dummy/config/environment"

class RailsPulseBenchmark
  WARMUP_TIME = 2
  BENCHMARK_TIME = 10
  SAMPLE_SIZE = 1000

  def initialize
    @results = {}
    setup_test_data
  end

  def run_all
    print_header

    benchmark_middleware_overhead
    benchmark_instrumentation_overhead
    benchmark_memory_impact
    benchmark_request_scenarios
    benchmark_job_scenarios
    benchmark_database_impact

    print_summary
    save_results
  end

  private

  def setup_test_data
    puts "Setting up test data..."

    # Clean up existing test data
    RailsPulse::Request.where("route_id IN (SELECT id FROM rails_pulse_routes WHERE path LIKE '/benchmark%')").delete_all
    RailsPulse::Route.where("path LIKE '/benchmark%'").delete_all

    # Create test routes
    @test_route_fast = RailsPulse::Route.find_or_create_by!(
      method: "GET",
      path: "/benchmark/fast"
    )

    @test_route_slow = RailsPulse::Route.find_or_create_by!(
      method: "GET",
      path: "/benchmark/slow"
    )

    @test_query = RailsPulse::Query.find_or_create_by!(
      normalized_sql: "SELECT * FROM users WHERE id = ?"
    )

    puts "Test data ready.\n"
  end

  def print_header
    puts "\n" + "=" * 100
    puts " " * 30 + "Rails Pulse Performance Benchmark"
    puts "=" * 100
    puts "\nEnvironment:"
    puts "  Ruby Version:    #{RUBY_VERSION}"
    puts "  Rails Version:   #{Rails.version}"
    puts "  Database:        #{ActiveRecord::Base.connection.adapter_name}"
    puts "  Rails Pulse:     #{RailsPulse::VERSION}"
    puts "  Machine:         #{`uname -m`.strip} (#{`uname -s`.strip})"
    puts "\nConfiguration:"
    puts "  Warmup Time:     #{WARMUP_TIME}s"
    puts "  Benchmark Time:  #{BENCHMARK_TIME}s"
    puts "  Sample Size:     #{SAMPLE_SIZE} iterations"
    puts "\n" + "=" * 100
  end

  def benchmark_middleware_overhead
    section_header("Middleware Overhead")

    # Create a minimal Rack application
    app = ->(env) { [ 200, { "Content-Type" => "text/plain" }, [ "OK" ] ] }
    middleware = RailsPulse::Middleware::RequestCollector.new(app)

    env = {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/test",
      "QUERY_STRING" => "",
      "rack.input" => StringIO.new,
      "rack.errors" => $stderr,
      "action_controller.instance" => Object.new
    }

    puts "\nMeasuring middleware call overhead:\n"

    # Baseline without middleware
    baseline = measure_time(SAMPLE_SIZE) { app.call(env.dup) }

    # With Rails Pulse enabled
    RailsPulse.configuration.enabled = true
    enabled = measure_time(SAMPLE_SIZE) { middleware.call(env.dup) }

    # With Rails Pulse disabled
    RailsPulse.configuration.enabled = false
    disabled = measure_time(SAMPLE_SIZE) { middleware.call(env.dup) }

    RailsPulse.configuration.enabled = true

    overhead_enabled = ((enabled - baseline) / SAMPLE_SIZE * 1000).round(4)
    overhead_disabled = ((disabled - baseline) / SAMPLE_SIZE * 1000).round(4)

    puts "  Baseline (no middleware):     #{format_time(baseline)} (#{SAMPLE_SIZE} calls)"
    puts "  Rails Pulse enabled:          #{format_time(enabled)} (#{SAMPLE_SIZE} calls)"
    puts "  Rails Pulse disabled:         #{format_time(disabled)} (#{SAMPLE_SIZE} calls)"
    puts "\n  Per-request overhead:"
    puts "    Enabled:  #{overhead_enabled}ms"
    puts "    Disabled: #{overhead_disabled}ms"
    puts "    Impact:   #{(overhead_enabled / baseline * 100).round(2)}% when enabled"

    @results[:middleware_overhead_ms] = overhead_enabled
  end

  def benchmark_instrumentation_overhead
    section_header("ActiveSupport Instrumentation Overhead")

    puts "\nMeasuring Rails instrumentation hooks:\n"

    # Simulate SQL query instrumentation
    payload = {
      sql: "SELECT * FROM users WHERE id = 1",
      name: "User Load",
      binds: [],
      type_casted_binds: []
    }

    event_name = "sql.active_record"

    # Baseline without subscribers
    ActiveSupport::Notifications.unsubscribe("sql.active_record")
    baseline = measure_time(SAMPLE_SIZE) do
      ActiveSupport::Notifications.instrument(event_name, payload) { }
    end

    # Reload Rails Pulse instrumentation
    load Rails.root.join("../../lib/rails_pulse/instrumentation.rb")

    # With Rails Pulse subscriber
    instrumented = measure_time(SAMPLE_SIZE) do
      ActiveSupport::Notifications.instrument(event_name, payload) { }
    end

    overhead = ((instrumented - baseline) / SAMPLE_SIZE * 1000).round(4)

    puts "  Baseline (no subscribers):    #{format_time(baseline)}"
    puts "  With Rails Pulse:             #{format_time(instrumented)}"
    puts "\n  Per-event overhead:           #{overhead}ms"
    puts "  Impact:                       #{(overhead / baseline * 100).round(2)}%"

    @results[:instrumentation_overhead_ms] = overhead
  end

  def benchmark_memory_impact
    section_header("Memory Allocation Impact")

    puts "\nMeasuring memory allocations:\n"

    # Memory profile for creating requests
    report = MemoryProfiler.report do
      100.times do
        req = RailsPulse::Request.create!(
          route: @test_route_fast,
          occurred_at: Time.current,
          duration: rand(50..200),
          status: 200,
          request_uuid: SecureRandom.uuid
        )

        # Add some operations
        3.times do
          RailsPulse::Operation.create!(
            request: req,
            query: @test_query,
            operation_type: "sql",
            label: "User Load",
            occurred_at: Time.current,
            duration: rand(5..50)
          )
        end
      end
    end

    total_kb = (report.total_allocated_memsize / 1024.0).round(2)
    per_request_kb = (total_kb / 100.0).round(2)

    puts "  Total memory allocated:       #{total_kb} KB (100 requests)"
    puts "  Per request:                  #{per_request_kb} KB"
    puts "  Allocated objects:            #{report.total_allocated}"
    puts "  Per request:                  #{report.total_allocated / 100} objects"
    puts "\n  Retained memory:              #{(report.total_retained_memsize / 1024.0).round(2)} KB"
    puts "  Retained objects:             #{report.total_retained}"

    @results[:memory_per_request_kb] = per_request_kb
    @results[:objects_per_request] = report.total_allocated / 100

    # Cleanup
    RailsPulse::Request.where(route: @test_route_fast).delete_all
  end

  def benchmark_request_scenarios
    section_header("Real-World Request Scenarios")

    scenarios = {
      "Fast request (minimal DB)" => -> { simulate_fast_request },
      "Moderate request (5 queries)" => -> { simulate_moderate_request },
      "Slow request (15 queries)" => -> { simulate_slow_request },
      "API request with JSON" => -> { simulate_api_request }
    }

    puts "\nSimulating different request patterns:\n"

    scenarios.each do |name, scenario|
      # With Rails Pulse enabled
      RailsPulse.configuration.enabled = true
      enabled_time = measure_time(100, &scenario)

      # With Rails Pulse disabled
      RailsPulse.configuration.enabled = false
      disabled_time = measure_time(100, &scenario)

      RailsPulse.configuration.enabled = true

      overhead = ((enabled_time - disabled_time) / 100 * 1000).round(3)

      puts "  #{name}:"
      puts "    Enabled:  #{format_time(enabled_time)} (100 requests)"
      puts "    Disabled: #{format_time(disabled_time)} (100 requests)"
      puts "    Overhead: #{overhead}ms per request"
      puts ""
    end
  end

  def benchmark_job_scenarios
    section_header("Background Job Tracking Overhead")

    return unless RailsPulse.configuration.track_jobs

    puts "\nMeasuring job execution overhead:\n"

    # Simple job
    simple_job = -> { User.count }

    # Database-heavy job
    heavy_job = -> do
      User.includes(:posts, :comments).limit(10).each do |user|
        user.posts.count
        user.comments.count
      end
    end

    jobs = {
      "Simple job (1 query)" => simple_job,
      "Heavy job (complex queries)" => heavy_job
    }

    jobs.each do |name, job|
      RailsPulse.configuration.track_jobs = true
      enabled_time = measure_time(50, &job)

      RailsPulse.configuration.track_jobs = false
      disabled_time = measure_time(50, &job)

      RailsPulse.configuration.track_jobs = true

      overhead = ((enabled_time - disabled_time) / 50 * 1000).round(3)

      puts "  #{name}:"
      puts "    Enabled:  #{format_time(enabled_time)} (50 jobs)"
      puts "    Disabled: #{format_time(disabled_time)} (50 jobs)"
      puts "    Overhead: #{overhead}ms per job"
      puts ""
    end
  end

  def benchmark_database_impact
    section_header("Database Query Performance")

    # Create sample data
    50.times do |i|
      RailsPulse::Request.create!(
        route: @test_route_fast,
        occurred_at: i.hours.ago,
        duration: rand(50..500),
        status: [ 200, 201, 404, 500 ].sample,
        request_uuid: SecureRandom.uuid
      )
    end

    puts "\nMeasuring Rails Pulse's own query performance:\n"

    queries = {
      "Average duration" => -> { RailsPulse::Request.average(:duration) },
      "Group by hour" => -> { RailsPulse::Request.group_by_hour(:occurred_at, last: 24).count },
      "Slow requests" => -> { RailsPulse::Request.where("duration > ?", 300).count },
      "Join with routes" => -> { RailsPulse::Request.joins(:route).group("rails_pulse_routes.path").count }
    }

    queries.each do |name, query|
      time = measure_time(100, &query)
      per_query = (time / 100 * 1000).round(3)

      puts "  #{name}:"
      puts "    Time: #{format_time(time)} (100 queries)"
      puts "    Average: #{per_query}ms per query"
      puts ""
    end

    # Cleanup
    RailsPulse::Request.where(route: @test_route_fast).delete_all
  end

  def simulate_fast_request
    User.count
    Post.first
  end

  def simulate_moderate_request
    User.includes(:posts).limit(5).each { |u| u.posts.count }
    Post.where(created_at: 1.week.ago..).count
    Comment.limit(10).pluck(:id, :content)
  end

  def simulate_slow_request
    User.includes(:posts, :comments).limit(10).each do |user|
      user.posts.where(created_at: 1.month.ago..).count
      user.comments.where(created_at: 1.week.ago..).count
    end
    Post.joins(:user, :comments).group("users.name").count
  end

  def simulate_api_request
    {
      users: User.count,
      posts: Post.count,
      recent: Post.where(created_at: 1.day.ago..).limit(5).pluck(:id, :title)
    }.to_json
  end

  def measure_time(iterations)
    GC.start
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    iterations.times { yield }

    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end_time - start_time
  end

  def format_time(seconds)
    if seconds < 1
      "#{(seconds * 1000).round(2)}ms"
    else
      "#{seconds.round(3)}s"
    end
  end

  def section_header(title)
    puts "\n" + "-" * 100
    puts "  #{title}"
    puts "-" * 100
  end

  def print_summary
    puts "\n" + "=" * 100
    puts " " * 40 + "SUMMARY"
    puts "=" * 100
    puts "\nKey Performance Metrics:"
    puts "  Middleware overhead:          #{@results[:middleware_overhead_ms]}ms per request"
    puts "  Instrumentation overhead:     #{@results[:instrumentation_overhead_ms]}ms per event"
    puts "  Memory per request:           #{@results[:memory_per_request_kb]} KB"
    puts "  Objects allocated:            #{@results[:objects_per_request]} per request"
    puts "\nConclusion:"

    total_overhead = @results[:middleware_overhead_ms] + @results[:instrumentation_overhead_ms]

    if total_overhead < 2
      puts "  ✅ EXCELLENT - Negligible overhead (< 2ms)"
    elsif total_overhead < 5
      puts "  ✅ GOOD - Low overhead (2-5ms)"
    elsif total_overhead < 10
      puts "  ⚠️  MODERATE - Noticeable overhead (5-10ms)"
    else
      puts "  ⚠️  HIGH - Consider optimizing (> 10ms)"
    end

    puts "\n" + "=" * 100
  end

  def save_results
    output_file = File.join(__dir__, "../docs/benchmark_results_#{Time.current.to_i}.json")

    File.write(output_file, JSON.pretty_generate({
      timestamp: Time.current.iso8601,
      environment: {
        ruby: RUBY_VERSION,
        rails: Rails.version,
        database: ActiveRecord::Base.connection.adapter_name,
        rails_pulse: RailsPulse::VERSION
      },
      results: @results
    }))

    puts "\n📊 Results saved to: #{output_file}"
  end
end

# Run benchmarks if executed directly
if __FILE__ == $0
  benchmark = RailsPulseBenchmark.new
  benchmark.run_all
end
