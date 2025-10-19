require "bundler/setup"
require "bundler/gem_tasks"

# Load environment variables from .env file
require "dotenv/load" if File.exist?(".env")

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

desc "Setup database for testing"
task :test_setup do
  database = ENV['DB'] || 'sqlite3'

  puts "\n" + "=" * 50
  puts "🛠️  Rails Pulse Test Setup"
  puts "=" * 50
  puts "Database: #{database.upcase}"
  puts "=" * 50
  puts

  begin
    # Remove schema.rb to ensure clean migration
    schema_file = "test/dummy/db/schema.rb"
    if File.exist?(schema_file)
      puts "🧹 Removing existing schema.rb file..."
      File.delete(schema_file)
    end

    case database.downcase
    when 'sqlite3', 'sqlite'
      puts "📦 Setting up SQLite database..."
      sh "RAILS_ENV=test bin/rails db:drop db:create db:migrate"

    when 'mysql2', 'mysql'
      puts "🐬 Setting up MySQL database..."
      sh "DB=mysql2 RAILS_ENV=test rails db:drop db:create db:migrate"

    when 'postgresql', 'postgres'
      puts "🐘 Setting up PostgreSQL database..."
      sh "DB=postgresql RAILS_ENV=test rails db:drop db:create db:migrate"

    else
      puts "⚠️  Unknown database: #{database}"
      puts "Supported databases: sqlite3, mysql2, postgresql"
      exit 1
    end

    puts "\n✅ Database setup complete!"
    puts "Ready to run: rake test"

  rescue => e
    puts "\n❌ Database setup failed!"
    puts "Error: #{e.message}"
    puts "\nTroubleshooting:"
    puts "• Ensure #{database} is installed and running"
    puts "• Check database credentials in test/dummy/config/database.yml"
    puts "• Verify RAILS_ENV=test environment is configured"
    exit 1
  end
end

desc "Run test suite"
task :test do
  database = ENV['DB'] || 'sqlite3'

  # Get Rails version from Gemfile.lock or fallback
  rails_version = begin
    require 'rails'
    Rails.version
  rescue LoadError
    # Try to get from Gemfile.lock
    gemfile_lock = File.read('Gemfile.lock') rescue nil
    if gemfile_lock && gemfile_lock.match(/rails \(([^)]+)\)/)
      $1
    else
      'unknown'
    end
  end

  puts "\n" + "=" * 50
  puts "💛 Rails Pulse Test Suite"
  puts "=" * 50
  puts "Database: #{database.upcase}"
  puts "Rails: #{rails_version}"
  puts "=" * 50
  puts

  sh "rails test test/controllers test/helpers test/instrumentation test/jobs test/models test/services"
end

desc "Setup database for specific Rails version and database"
task :test_setup_for_version, [ :database, :rails_version ] do |t, args|
  database = args[:database] || ENV['DB'] || 'sqlite3'
  rails_version = args[:rails_version] || 'rails-8-0'

  puts "\n" + "=" * 50
  puts "🛠️  Rails Pulse Test Setup"
  puts "=" * 50
  puts "Database: #{database.upcase}"
  puts "Rails: #{rails_version.upcase.gsub('-', ' ')}"
  puts "=" * 50
  puts

  begin
    # Remove schema.rb to ensure clean migration
    schema_file = "test/dummy/db/schema.rb"
    if File.exist?(schema_file)
      puts "🧹 Removing existing schema.rb file..."
      File.delete(schema_file)
    end

    if rails_version == "rails-8-0" && database == "sqlite3"
      # Use current default setup
      puts "📦 Setting up #{database.upcase} database with Rails 8.0..."
      sh "RAILS_ENV=test bin/rails db:drop db:create db:migrate"
    else
      # Use appraisal with specific database and Rails version
      puts "📦 Setting up #{database.upcase} database with #{rails_version.upcase.gsub('-', ' ')}..."
      sh "DB=#{database} bundle exec appraisal #{rails_version} rails db:drop db:create db:migrate RAILS_ENV=test"
    end

    puts "\n✅ Database setup complete for #{database.upcase} + #{rails_version.upcase.gsub('-', ' ')}!"

  rescue => e
    puts "\n❌ Database setup failed!"
    puts "Error: #{e.message}"
    exit 1
  end
end

desc "Test all database and Rails version combinations"
task :test_matrix do
  databases = %w[sqlite3 postgresql mysql2]
  rails_versions = %w[rails-7-2 rails-8-0]

  failed_combinations = []
  total_combinations = databases.size * rails_versions.size
  current = 0

  puts "\n" + "=" * 60
  puts "🚀 Rails Pulse Full Test Matrix"
  puts "=" * 60
  puts "Testing #{total_combinations} combinations..."
  puts "=" * 60

  databases.each do |database|
    rails_versions.each do |rails_version|
      current += 1

      puts "\n[#{current}/#{total_combinations}] Testing: #{database.upcase} + #{rails_version.upcase.gsub('-', ' ')}"
      puts "-" * 50

      begin
        # First setup the database for this specific combination
        Rake::Task[:test_setup_for_version].reenable
        Rake::Task[:test_setup_for_version].invoke(database, rails_version)

        # Then run the tests
        if rails_version == "rails-8-0" && database == "sqlite3"
          # Current default setup
          sh "bundle exec rake test"
        else
          # Use appraisal with specific database
          sh "DB=#{database} bundle exec appraisal #{rails_version} rake test"
        end

        puts "✅ PASSED: #{database} + #{rails_version}"

      rescue => e
        puts "❌ FAILED: #{database} + #{rails_version}"
        puts "   Error: #{e.message}"
        failed_combinations << "#{database} + #{rails_version}"
      end
    end
  end

  puts "\n" + "=" * 60
  puts "🏁 Test Matrix Results"
  puts "=" * 60

  if failed_combinations.empty?
    puts "🎉 All #{total_combinations} combinations passed!"
  else
    puts "✅ Passed: #{total_combinations - failed_combinations.size}/#{total_combinations}"
    puts "❌ Failed combinations:"
    failed_combinations.each { |combo| puts "   • #{combo}" }
    exit 1
  end
end

desc "Pre-release testing with comprehensive checks"
task :test_release do
  puts "\n" + "=" * 70
  puts "🚀 Rails Pulse Pre-Release Validation"
  puts "=" * 70
  puts

  failed_tasks = []
  current_step = 0
  total_steps = 7

  # Step 1: Git status check
  current_step += 1
  begin
    puts "\n[#{current_step}/#{total_steps}] Checking git status..."
    puts "-" * 70

    git_status = `git status --porcelain`.strip
    if !git_status.empty?
      puts "❌ Git working directory is not clean!"
      puts "\nUncommitted changes:"
      puts git_status
      puts "\nPlease commit or stash your changes before running pre-release tests."
      failed_tasks << "git_status_check"
    else
      puts "✅ Git working directory is clean"
    end
  rescue => e
    puts "⚠️  Warning: Could not check git status (#{e.message})"
  end

  # Step 2: RuboCop linting
  current_step += 1
  begin
    puts "\n[#{current_step}/#{total_steps}] Running RuboCop linting..."
    puts "-" * 70
    sh "bundle exec rubocop"
    puts "✅ Code style checks passed!"
  rescue => e
    puts "❌ RuboCop linting failed!"
    puts "   Error: #{e.message}"
    failed_tasks << "rubocop"
  end

  # Step 3: Install Node dependencies
  current_step += 1
  begin
    puts "\n[#{current_step}/#{total_steps}] Installing Node dependencies..."
    puts "-" * 70
    sh "npm install"
    puts "✅ Node dependencies installed!"
  rescue => e
    puts "❌ npm install failed!"
    puts "   Error: #{e.message}"
    failed_tasks << "npm_install"
  end

  # Step 4: Build and verify assets
  current_step += 1
  begin
    puts "\n[#{current_step}/#{total_steps}] Building production assets..."
    puts "-" * 70
    sh "npm run build"

    # Verify assets were built
    assets_dir = "public/rails-pulse-assets"
    if Dir.exist?(assets_dir) && !Dir.empty?(assets_dir)
      puts "✅ Assets built successfully!"
      puts "   Location: #{assets_dir}"
    else
      puts "❌ Assets directory is missing or empty!"
      failed_tasks << "asset_build_verification"
    end
  rescue => e
    puts "❌ Asset building failed!"
    puts "   Error: #{e.message}"
    failed_tasks << "npm_build"
  end

  # Step 5: Verify gem builds
  current_step += 1
  begin
    puts "\n[#{current_step}/#{total_steps}] Verifying gem builds correctly..."
    puts "-" * 70
    sh "gem build rails_pulse.gemspec"

    # Clean up the built gem
    built_gems = Dir.glob("rails_pulse-*.gem")
    built_gems.each { |gem_file| File.delete(gem_file) }

    puts "✅ Gem builds successfully!"
  rescue => e
    puts "❌ Gem build failed!"
    puts "   Error: #{e.message}"
    failed_tasks << "gem_build"
  end

  # Step 6: Run generator tests
  current_step += 1
  begin
    puts "\n[#{current_step}/#{total_steps}] Running generator tests..."
    puts "-" * 70
    sh "./bin/test_generators"
    puts "✅ Generator tests passed!"
  rescue => e
    puts "❌ Generator tests failed!"
    puts "   Error: #{e.message}"
    failed_tasks << "test_generators"
  end

  # Step 7: Run full test matrix with system tests
  current_step += 1
  begin
    puts "\n[#{current_step}/#{total_steps}] Running full test matrix with system tests..."
    puts "-" * 70
    sh "BROWSER=true rake test_matrix"
    puts "✅ Test matrix passed!"
  rescue => e
    puts "❌ Test matrix failed!"
    puts "   Error: #{e.message}"
    failed_tasks << "test_matrix"
  end

  # Print final results
  puts "\n" + "=" * 70
  puts "🏁 Pre-Release Validation Results"
  puts "=" * 70

  if failed_tasks.empty?
    puts "🎉 All pre-release checks passed!"
    puts "\n✅ Ready for release!"
    puts "\nNext steps:"
    puts "  1. Update version in lib/rails_pulse/version.rb"
    puts "  2. Update Gemfile.lock files for all Rails versions"
    puts "  3. Follow the release process in docs/releasing.md"
  else
    puts "❌ Failed checks (#{failed_tasks.size}/#{total_steps}):"
    failed_tasks.each { |task| puts "   • #{task}" }
    puts "\n⚠️  Fix these issues before releasing."
    exit 1
  end
end


task default: :test
