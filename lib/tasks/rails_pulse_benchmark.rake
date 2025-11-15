begin
  require "benchmark"
  require "benchmark/ips"
  require "memory_profiler"
rescue LoadError => e
  # Benchmark gems not available - tasks will show error if run
end

namespace :rails_pulse do
  namespace :benchmark do
    desc "Run comprehensive performance benchmarks for Rails Pulse"
    task all: :environment do
      unless defined?(Benchmark::IPS) && defined?(MemoryProfiler)
        puts "❌ Benchmark gems not installed. Add to your Gemfile:"
        puts "  gem 'benchmark-ips'"
        puts "  gem 'memory_profiler'"
        puts "\nThen run: bundle install"
        exit 1
      end

      puts "\n" + "=" * 80
      puts "Rails Pulse Performance Benchmark Suite"
      puts "=" * 80
      puts "\nEnvironment:"
      puts "  Ruby: #{RUBY_VERSION}"
      puts "  Rails: #{Rails.version}"
      puts "  Database: #{ActiveRecord::Base.connection.adapter_name}"
      puts "  Rails Pulse: #{RailsPulse::VERSION}"
      puts "\n"

      # Run all benchmarks
      Rake::Task["rails_pulse:benchmark:memory"].invoke
      Rake::Task["rails_pulse:benchmark:request_overhead"].invoke
      Rake::Task["rails_pulse:benchmark:middleware"].invoke
      Rake::Task["rails_pulse:benchmark:job_tracking"].invoke
      Rake::Task["rails_pulse:benchmark:database_queries"].invoke

      puts "\n" + "=" * 80
      puts "Benchmark suite completed!"
      puts "=" * 80
    end

    desc "Benchmark memory usage with and without Rails Pulse"
    task memory: :environment do
      puts "\n" + "-" * 80
      puts "Memory Usage Benchmark"
      puts "-" * 80

      # Ensure Rails Pulse is enabled
      original_enabled = RailsPulse.configuration.enabled
      RailsPulse.configuration.enabled = true

      # Baseline memory (Rails Pulse disabled)
      RailsPulse.configuration.enabled = false
      GC.start
      baseline_memory = GC.stat(:total_allocated_objects)

      # Create some test data
      route = RailsPulse::Route.find_or_create_by!(
        method: "GET",
        path: "/benchmark/test"
      )

      # Memory with Rails Pulse enabled
      RailsPulse.configuration.enabled = true
      GC.start
      enabled_memory = GC.stat(:total_allocated_objects)

      # Profile memory for creating a request
      report = MemoryProfiler.report do
        10.times do
          RailsPulse::Request.create!(
            route: route,
            occurred_at: Time.current,
            duration: rand(50..500),
            status: 200,
            request_uuid: SecureRandom.uuid
          )
        end
      end

      puts "\nMemory Allocation Summary:"
      puts "  Total allocated: #{report.total_allocated_memsize / 1024.0} KB"
      puts "  Total retained: #{report.total_retained_memsize / 1024.0} KB"
      puts "  Allocated objects: #{report.total_allocated}"
      puts "  Retained objects: #{report.total_retained}"

      puts "\nPer-Request Memory Overhead:"
      puts "  ~#{(report.total_allocated_memsize / 10.0 / 1024.0).round(2)} KB per request"

      # Restore original state
      RailsPulse.configuration.enabled = original_enabled
    end

    desc "Benchmark request processing overhead"
    task request_overhead: :environment do
      puts "\n" + "-" * 80
      puts "Request Processing Overhead Benchmark"
      puts "-" * 80

      # Setup test data
      route = RailsPulse::Route.find_or_create_by!(
        method: "GET",
        path: "/benchmark/test"
      )

      query = RailsPulse::Query.find_or_create_by!(
        normalized_sql: "SELECT * FROM users WHERE id = ?"
      )

      puts "\nIterations per second (higher is better):\n"

      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report("Request creation (baseline)") do
          RailsPulse::Request.new(
            route: route,
            occurred_at: Time.current,
            duration: 100,
            status: 200,
            request_uuid: SecureRandom.uuid
          )
        end

        x.report("Request creation + save") do
          req = RailsPulse::Request.create!(
            route: route,
            occurred_at: Time.current,
            duration: 100,
            status: 200,
            request_uuid: SecureRandom.uuid
          )
          req.destroy
        end

        x.report("Request + Operation") do
          req = RailsPulse::Request.create!(
            route: route,
            occurred_at: Time.current,
            duration: 100,
            status: 200,
            request_uuid: SecureRandom.uuid
          )
          RailsPulse::Operation.create!(
            request: req,
            query: query,
            operation_type: "sql",
            label: "User Load",
            occurred_at: Time.current,
            duration: 10
          )
          req.destroy
        end

        x.compare!
      end

      puts "\nAbsolute timing comparison:\n"
      result = Benchmark.measure do
        1000.times do
          req = RailsPulse::Request.create!(
            route: route,
            occurred_at: Time.current,
            duration: 100,
            status: 200,
            request_uuid: SecureRandom.uuid
          )
          req.destroy
        end
      end

      puts "  1000 requests: #{(result.real * 1000).round(2)}ms total"
      puts "  Average per request: #{result.real.round(5)}ms"
    end

    desc "Benchmark middleware overhead"
    task middleware: :environment do
      puts "\n" + "-" * 80
      puts "Middleware Overhead Benchmark"
      puts "-" * 80

      # Create mock request environment
      env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/test",
        "QUERY_STRING" => "",
        "rack.input" => StringIO.new,
        "rack.errors" => $stderr,
        "action_dispatch.request_id" => SecureRandom.uuid
      }

      app = ->(env) { [ 200, { "Content-Type" => "text/plain" }, [ "OK" ] ] }
      middleware = RailsPulse::Middleware::RequestCollector.new(app)

      puts "\nMiddleware performance:\n"

      # Benchmark with Rails Pulse enabled
      RailsPulse.configuration.enabled = true
      enabled_time = Benchmark.measure do
        1000.times do
          test_env = env.dup
          test_env["action_dispatch.request_id"] = SecureRandom.uuid
          middleware.call(test_env)
        end
      end

      # Benchmark with Rails Pulse disabled
      RailsPulse.configuration.enabled = false
      disabled_time = Benchmark.measure do
        1000.times do
          test_env = env.dup
          test_env["action_dispatch.request_id"] = SecureRandom.uuid
          middleware.call(test_env)
        end
      end

      # Benchmark without middleware
      baseline_time = Benchmark.measure do
        1000.times { app.call(env.dup) }
      end

      overhead_enabled = (enabled_time.real - baseline_time.real) * 1000 / 1000
      overhead_disabled = (disabled_time.real - baseline_time.real) * 1000 / 1000

      puts "  Baseline (no middleware): #{(baseline_time.real * 1000).round(2)}ms (1000 requests)"
      puts "  With Rails Pulse enabled: #{(enabled_time.real * 1000).round(2)}ms (1000 requests)"
      puts "  With Rails Pulse disabled: #{(disabled_time.real * 1000).round(2)}ms (1000 requests)"
      puts "\n  Overhead per request (enabled): #{overhead_enabled.round(3)}ms"
      puts "  Overhead per request (disabled): #{overhead_disabled.round(3)}ms"

      # Restore
      RailsPulse.configuration.enabled = true
    end

    desc "Benchmark job tracking overhead"
    task job_tracking: :environment do
      puts "\n" + "-" * 80
      puts "Background Job Tracking Overhead Benchmark"
      puts "-" * 80

      # Skip if job tracking is disabled
      unless RailsPulse.configuration.track_jobs
        puts "\n  ⚠️  Job tracking is disabled - skipping benchmark"
        next
      end

      # Create a simple test job
      test_job_class = Class.new(ApplicationJob) do
        def perform(value)
          # Simulate some work
          sleep(0.001)
          value * 2
        end
      end

      puts "\nJob execution overhead:\n"

      # Benchmark with job tracking enabled
      RailsPulse.configuration.track_jobs = true
      enabled_time = Benchmark.measure do
        100.times do |i|
          test_job_class.new.perform(i)
        end
      end

      # Benchmark with job tracking disabled
      RailsPulse.configuration.track_jobs = false
      disabled_time = Benchmark.measure do
        100.times do |i|
          test_job_class.new.perform(i)
        end
      end

      overhead = (enabled_time.real - disabled_time.real) * 1000 / 100

      puts "  With tracking enabled: #{(enabled_time.real * 1000).round(2)}ms (100 jobs)"
      puts "  With tracking disabled: #{(disabled_time.real * 1000).round(2)}ms (100 jobs)"
      puts "\n  Overhead per job: #{overhead.round(3)}ms"

      # Restore
      RailsPulse.configuration.track_jobs = true
    end

    desc "Benchmark database query overhead"
    task database_queries: :environment do
      puts "\n" + "-" * 80
      puts "Database Query Overhead Benchmark"
      puts "-" * 80

      # Create test route for queries
      route = RailsPulse::Route.find_or_create_by!(
        method: "GET",
        path: "/benchmark/queries"
      )

      puts "\nQuery performance comparison:\n"

      # Test 1: Simple aggregation query
      puts "  1. Average request duration calculation:"
      time_enabled = Benchmark.measure do
        100.times { RailsPulse::Request.average(:duration) }
      end

      RailsPulse.configuration.enabled = false
      time_disabled = Benchmark.measure do
        100.times { RailsPulse::Request.average(:duration) }
      end
      RailsPulse.configuration.enabled = true

      puts "     Enabled: #{(time_enabled.real * 1000).round(2)}ms (100 queries)"
      puts "     Disabled: #{(time_disabled.real * 1000).round(2)}ms (100 queries)"
      puts "     Overhead: #{((time_enabled.real - time_disabled.real) * 10).round(3)}ms per query"

      # Test 2: Complex joins and grouping
      puts "\n  2. Requests grouped by hour with joins:"
      time_complex = Benchmark.measure do
        10.times do
          RailsPulse::Request
            .joins(:route)
            .group("DATE_TRUNC('hour', occurred_at)")
            .average(:duration)
        end
      end

      puts "     Time: #{(time_complex.real * 1000).round(2)}ms (10 queries)"
      puts "     Average: #{(time_complex.real * 100).round(3)}ms per query"

      # Test 3: Summary aggregation
      puts "\n  3. Summary data aggregation:"
      time_summary = Benchmark.measure do
        10.times do
          RailsPulse::Summary
            .where("period_start > ?", 24.hours.ago)
            .group(:period_type)
            .average(:avg_duration)
        end
      end

      puts "     Time: #{(time_summary.real * 1000).round(2)}ms (10 queries)"
      puts "     Average: #{(time_summary.real * 100).round(3)}ms per query"
    end

    desc "Generate benchmark report and save to docs"
    task report: :environment do
      require "fileutils"

      puts "\n" + "=" * 80
      puts "Generating Performance Benchmark Report"
      puts "=" * 80

      output_file = Rails.root.join("../../docs/benchmark_results.md")
      FileUtils.mkdir_p(File.dirname(output_file))

      File.open(output_file, "w") do |f|
        f.puts "# Rails Pulse Performance Benchmark Results"
        f.puts ""
        f.puts "**Generated:** #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
        f.puts ""
        f.puts "## Environment"
        f.puts ""
        f.puts "- **Ruby:** #{RUBY_VERSION}"
        f.puts "- **Rails:** #{Rails.version}"
        f.puts "- **Database:** #{ActiveRecord::Base.connection.adapter_name}"
        f.puts "- **Rails Pulse:** #{RailsPulse::VERSION}"
        f.puts ""
        f.puts "## Summary"
        f.puts ""
        f.puts "This report contains automated performance benchmarks measuring Rails Pulse's overhead."
        f.puts ""
        f.puts "---"
        f.puts ""
        f.puts "*For full benchmark output, run:* `rails rails_pulse:benchmark:all`"
      end

      puts "\n✅ Report saved to: #{output_file}"

      # Run full benchmark suite
      Rake::Task["rails_pulse:benchmark:all"].invoke
    end
  end
end
