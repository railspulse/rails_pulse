# frozen_string_literal: true

# SimpleCov configuration for Rails Pulse. Configuration only — `SimpleCov.start`
# is called explicitly from test/dummy/config/boot.rb, before Rails boots, so
# engine files loaded during boot are tracked (a `.simplecov` that calls
# `.start` itself is deprecated: timing is implicit and can't be controlled).
SimpleCov.configure do
  # Use Rails profile as base configuration
  load_profile "rails"

  # Set minimum coverage thresholds
  minimum_coverage 90
  coverage(:line) { minimum 80, per: :file }

  # Enable branch coverage for better visibility into conditional logic
  enable_coverage :branch

  # Filters - exclude test code and dummy app
  skip "/test/"
  skip "/config/"
  skip "/test/dummy/"
  skip "/db/"
  skip "/lib/generators/rails_pulse/templates/"

  # Exclude files that cannot meaningfully be covered:
  # - version.rb is a single constant with nothing to test
  # - delayed_job_plugin.rb is only loaded when delayed_job gem is present (not a test dependency)
  skip "/lib/rails_pulse/version.rb"
  skip "/lib/rails_pulse/adapters/delayed_job_plugin.rb"

  # Rake task files are loaded by the task tests but only ever partially
  # executed — a task body runs only when that task is invoked, and how many
  # run depends on test ordering and on which tests skip. That makes the
  # per-file gate flaky rather than informative: the same commit passes or
  # fails depending on the seed. `rake test_migrations` already disables
  # coverage for exactly this reason; this is the same problem in the main
  # phase. The tasks are covered behaviourally by test/lib/tasks.
  skip %r{\A/lib/tasks/}

  # Groups - organize coverage by component type
  group "Models", "app/models"
  group "Controllers", "app/controllers"
  group "Services", "app/services"
  group "Concerns", "app/controllers/concerns"
  group "Card Components", "app/models/rails_pulse/*/cards"
  group "Chart Components", "app/models/rails_pulse/dashboard/charts"
  group "Lib", "lib/rails_pulse"
  group "Generators", "lib/generators"

  # Track all files even if they have no coverage (shows untested code)
  cover "{app,lib}/**/*.rb"

  # Use appropriate formatter based on environment
  if ENV["CI"]
    formatter SimpleCov::Formatter::SimpleFormatter
  else
    formatter SimpleCov::Formatter::HTMLFormatter
  end

  # Coverage output directory
  coverage_dir "coverage"
end
