# frozen_string_literal: true

# SimpleCov configuration for Rails Pulse
# Automatically loaded when COVERAGE=true
SimpleCov.start do
  # Use Rails profile as base configuration
  load_profile "rails"

  # Set minimum coverage thresholds
  minimum_coverage 90
  minimum_coverage_by_file 80

  # Enable branch coverage for better visibility into conditional logic
  enable_coverage :branch

  # Filters - exclude test code and dummy app
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/test/dummy/"
  add_filter "/db/"
  add_filter "/lib/generators/rails_pulse/templates/"

  # Exclude files that cannot meaningfully be covered:
  # - version.rb is a single constant with nothing to test
  # - delayed_job_plugin.rb is only loaded when delayed_job gem is present (not a test dependency)
  add_filter "/lib/rails_pulse/version.rb"
  add_filter "/lib/rails_pulse/adapters/delayed_job_plugin.rb"

  # Groups - organize coverage by component type
  add_group "Models", "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Services", "app/services"
  add_group "Concerns", "app/controllers/concerns"
  add_group "Card Components", "app/models/rails_pulse/*/cards"
  add_group "Chart Components", "app/models/rails_pulse/dashboard/charts"
  add_group "Lib", "lib/rails_pulse"
  add_group "Generators", "lib/generators"

  # Track all files even if they have no coverage (shows untested code)
  track_files "{app,lib}/**/*.rb"

  # Use appropriate formatter based on environment
  if ENV["CI"]
    formatter SimpleCov::Formatter::SimpleFormatter
  else
    formatter SimpleCov::Formatter::HTMLFormatter
  end

  # Coverage output directory
  coverage_dir "coverage"
end
