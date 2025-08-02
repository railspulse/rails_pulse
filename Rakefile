require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

load "rails/tasks/statistics.rake"

require "bundler/gem_tasks"

# Test tasks
namespace :test do
  desc "Run unit tests (fastest - uses in-memory database)"
  task :unit do
    ENV["TEST_TYPE"] = "unit"
    ENV["MEMORY_DATABASE"] = "true"
    Rake::Task["test:run_unit"].invoke
  end

  desc "Run functional tests"
  task :functional do
    ENV["TEST_TYPE"] = "functional"
    ENV["MEMORY_DATABASE"] = "true"
    Rake::Task["test:run_functional"].invoke
  end

  desc "Run integration tests"
  task :integration do
    ENV["TEST_TYPE"] = "integration"
    ENV["MEMORY_DATABASE"] = "false"
    Rake::Task["test:run_integration"].invoke
  end

  desc "Run all tests (unit, functional, integration)"
  task :all do
    %w[unit functional integration].each do |test_type|
      puts "\n=== Running #{test_type} tests ==="
      Rake::Task["test:#{test_type}"].invoke
    end
  end

  desc "Run unit tests (alias for test:unit)"
  task units: :unit

  desc "Run functional tests (alias for test:functional)"
  task functionals: :functional

  desc "Run integration tests (alias for test:integration)"
  task integrations: :integration

  desc "Run tests with speed optimizations"
  task fast: :unit


  # Internal tasks
  task :run_unit do
    sh "rails test test/models test/middleware test/lib test/support"
  end

  task :run_functional do
    sh "rails test test/controllers test/helpers"
  end

  task :run_integration do
    sh "rails test test/integration"
  end
end

# Speed-optimized test task (unit tests only)
desc "Run fast unit tests only"
task test_fast: "test:unit"

# Override default test task to run all tests
desc "Run all tests"
task test: "test:all"

# Simplified database testing tasks
namespace :test do
  desc "Run tests with SQLite (default)"
  task :sqlite do
    puts "🗂️  Testing with SQLite..."
    Rake::Task["test:all"].invoke
  end

  desc "Run tests with PostgreSQL"
  task :postgresql do
    puts "🐘 Testing with PostgreSQL..."
    env = ENV.to_h.merge(
      "DATABASE_ADAPTER" => "postgresql",
      "FORCE_DB_CONFIG" => "true"
    )
    system(env, "rails test:all") || raise("PostgreSQL tests failed")
  end

  desc "Run tests with MySQL"
  task :mysql do
    puts "🐬 Testing with MySQL..."
    env = ENV.to_h.merge(
      "DATABASE_ADAPTER" => "mysql2",
      "FORCE_DB_CONFIG" => "true",
      "PARALLEL_WORKERS" => "1"
    )
    system(env, "rails test:all") || raise("MySQL tests failed")
  end

  desc "Run test matrix (SQLite + PostgreSQL + MySQL)"
  task :matrix do
    puts "\n🧪 Running test matrix...\n"

    databases = [
      { name: "SQLite", env: {}, emoji: "🗂️" },
      { name: "PostgreSQL", env: { "DATABASE_ADAPTER" => "postgresql", "FORCE_DB_CONFIG" => "true" }, emoji: "🐘" },
      { name: "MySQL", env: { "DATABASE_ADAPTER" => "mysql2", "FORCE_DB_CONFIG" => "true", "PARALLEL_WORKERS" => "1" }, emoji: "🐬" }
    ]

    results = {}

    databases.each do |db|
      puts "\n" + "="*60
      puts "#{db[:emoji]} Testing with #{db[:name]}..."
      puts "="*60

      begin
        env = ENV.to_h.merge(db[:env])
        success = system(env, "rails test:all")

        results[db[:name]] = success ? "✅ PASSED" : "❌ FAILED"
      rescue => e
        results[db[:name]] = "❌ FAILED"
        puts "Error: #{e.message}"
      end
    end

    # Print summary
    puts "\n" + "="*60
    puts "🏁 TEST MATRIX SUMMARY"
    puts "="*60
    results.each do |db, status|
      puts "#{status} #{db}"
    end
    puts "="*60

    # Fail if any tests failed
    failed_count = results.values.count { |status| status.include?("FAILED") }
    if failed_count > 0
      puts "\n❌ #{failed_count} database(s) failed tests"
      exit 1
    else
      puts "\n🎉 All databases passed!"
    end
  end

  desc "Run full test matrix (SQLite + PostgreSQL + MySQL)"
  task :matrix_full do
    puts "\n🧪 Running full test matrix...\n"

    databases = [
      { name: "SQLite", env: {}, emoji: "🗂️" },
      { name: "PostgreSQL", env: { "DATABASE_ADAPTER" => "postgresql", "FORCE_DB_CONFIG" => "true" }, emoji: "🐘" },
      { name: "MySQL", env: { "DATABASE_ADAPTER" => "mysql2", "FORCE_DB_CONFIG" => "true", "PARALLEL_WORKERS" => "1" }, emoji: "🐬" }
    ]

    results = {}

    databases.each do |db|
      puts "\n" + "="*60
      puts "#{db[:emoji]} Testing with #{db[:name]}..."
      puts "="*60

      begin
        env = ENV.to_h.merge(db[:env])
        success = system(env, "rails test:all")

        results[db[:name]] = success ? "✅ PASSED" : "❌ FAILED"
      rescue => e
        results[db[:name]] = "❌ FAILED"
        puts "Error: #{e.message}"
      end
    end

    # Print summary
    puts "\n" + "="*60
    puts "🏁 FULL TEST MATRIX SUMMARY"
    puts "="*60
    results.each do |db, status|
      puts "#{status} #{db}"
    end
    puts "="*60

    # Fail if any tests failed
    failed_count = results.values.count { |status| status.include?("FAILED") }
    if failed_count > 0
      puts "\n❌ #{failed_count} database(s) failed tests"
      exit 1
    else
      puts "\n🎉 All databases passed!"
    end
  end
end

# Helper methods
def mysql_available?
  system("mysql --version > /dev/null 2>&1")
end

def postgresql_available?
  system("psql --version > /dev/null 2>&1")
end
