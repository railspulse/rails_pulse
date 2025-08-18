require "bundler/setup"

# Load environment variables from .env file
require "dotenv/load" if File.exist?(".env")

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"
load "rails/tasks/statistics.rake"

require "bundler/gem_tasks"

# Test tasks
namespace :test do
  desc "Run unit tests (models, helpers, services)"
  task :unit do
    sh "rails test test/models test/helpers test/services test/support"
  end

  desc "Run functional tests (controllers)"
  task :functional do
    sh "rails test test/controllers"
  end

  desc "Run integration tests"
  task :integration do
    sh "rails test test/integration test/system"
  end

  desc "Run all tests"
  task :all do
    sh "rails test"
  end

  desc "Run tests across all database and Rails version combinations"
  task :matrix do
    databases = [ "sqlite3", "postgresql", "mysql2" ]
    rails_versions = [ "rails-7-2", "rails-8-0" ]

    failed_combinations = []

    databases.each do |database|
      rails_versions.each do |rails_version|
        puts "\n" + "=" * 80
        puts "🧪 Testing: #{database.upcase} + #{rails_version.upcase}"
        puts "=" * 80

        begin
          gemfile = "gemfiles/#{rails_version.gsub('-', '_')}.gemfile"

          # Set environment variables
          env_vars = {
            "DATABASE_ADAPTER" => database,
            "BUNDLE_GEMFILE" => gemfile,
            "FORCE_DB_CONFIG" => "true"
          }

          # Add database-specific environment variables
          case database
          when "postgresql"
            env_vars.merge!({
              "POSTGRES_USERNAME" => ENV.fetch("POSTGRES_USERNAME", "postgres"),
              "POSTGRES_PASSWORD" => ENV.fetch("POSTGRES_PASSWORD", ""),
              "POSTGRES_HOST" => ENV.fetch("POSTGRES_HOST", "localhost"),
              "POSTGRES_PORT" => ENV.fetch("POSTGRES_PORT", "5432")
            })
          when "mysql2"
            env_vars.merge!({
              "MYSQL_USERNAME" => ENV.fetch("MYSQL_USERNAME", "root"),
              "MYSQL_PASSWORD" => ENV.fetch("MYSQL_PASSWORD", "password"),
              "MYSQL_HOST" => ENV.fetch("MYSQL_HOST", "localhost"),
              "MYSQL_PORT" => ENV.fetch("MYSQL_PORT", "3306")
            })
          end

          # Build environment string
          env_string = env_vars.map { |k, v| "#{k}=#{v}" }.join(" ")

          # Run the test command
          sh "#{env_string} bundle exec rails test:all"

          puts "✅ PASSED: #{database} + #{rails_version}"

        rescue => e
          puts "❌ FAILED: #{database} + #{rails_version}"
          puts "Error: #{e.message}"
          failed_combinations << "#{database} + #{rails_version}"
        end
      end
    end

    puts "\n" + "=" * 80
    puts "🏁 Test Matrix Results"
    puts "=" * 80

    if failed_combinations.empty?
      puts "✅ All combinations passed!"
    else
      puts "❌ Failed combinations:"
      failed_combinations.each { |combo| puts "  - #{combo}" }
      exit 1
    end
  end
end

# Override default test task
desc "Run all tests"
task test: "test:all"
