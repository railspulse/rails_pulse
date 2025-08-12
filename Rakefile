require "bundler/setup"

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
end

# Override default test task
desc "Run all tests"
task test: "test:all"
