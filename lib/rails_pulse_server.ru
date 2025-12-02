# Load Rails environment - try multiple locations
if File.exist?("test/dummy/config/environment.rb")
  # Running from Rails Pulse gem root (for development/testing)
  require_relative "../test/dummy/config/environment"
elsif File.exist?("config/environment.rb")
  # Running from a Rails app that has Rails Pulse installed
  require File.expand_path("config/environment", Dir.pwd)
else
  # Standalone mode - load minimal dependencies
  puts "=" * 80
  puts "RailsPulse Dashboard (Standalone Mode)"
  puts "=" * 80

  require "bundler/setup"
  require "active_support/all"
  require "active_record"

  $LOAD_PATH.unshift File.expand_path("../lib", __dir__)
  require "rails_pulse"

  # Load database configuration from environment
  db_config = if ENV["DATABASE_URL"]
    { url: ENV["DATABASE_URL"] }
  elsif File.exist?("config/database.yml")
    require "yaml"
    db_yml = YAML.load_file("config/database.yml", aliases: true)
    rails_env = ENV.fetch("RAILS_ENV", "production")

    rails_pulse_config = db_yml.dig(rails_env, "rails_pulse")
    if rails_pulse_config
      rails_pulse_config
    else
      puts "WARNING: No 'rails_pulse' database found in config/database.yml, using primary connection"
      db_yml[rails_env]
    end
  else
    raise "Database configuration not found. Set DATABASE_URL or provide config/database.yml"
  end

  puts "Connecting to database: #{db_config[:database] || db_config[:url]&.split('@')&.last}"

  # Configure RailsPulse for dashboard-only mode
  RailsPulse.configure do |config|
    # CRITICAL: Disable tracking in dashboard process
    config.enabled = false

    # Configure database connection
    config.connects_to = { database: db_config }
  end

  # Establish database connection
  RailsPulse::ApplicationRecord.establish_connection(db_config)

  puts "Dashboard ready on port #{ENV.fetch('PORT', 3001)}"
  puts "=" * 80
end

# Disable output buffering so logs appear immediately
$stdout.sync = true
$stderr.sync = true

# Build the Rack app with session support
require "rack/session/cookie"
require "securerandom"

# Simple Rack app that just serves the dashboard
class DashboardApp
  def initialize
    @dashboard = RailsPulse::Engine
  end

  def call(env)
    # Health check endpoint
    if env["PATH_INFO"] == "/health"
      healthy = RailsPulse::Tracker.healthy? rescue false
      status_code = healthy ? 200 : 503

      return [
        status_code,
        { "content-type" => "application/json" },
        [ {
          status: healthy ? "ok" : "unhealthy",
          mode: "dashboard",
          database: healthy ? "connected" : "disconnected",
          timestamp: Time.now.iso8601
        }.to_json ]
      ]
    end

    # All other requests go to RailsPulse Engine (dashboard)
    @dashboard.call(env)
  end
end

# Add session middleware for the dashboard
# Require SECRET_KEY_BASE for security
secret_key = ENV.fetch("SECRET_KEY_BASE") do
  raise "SECRET_KEY_BASE environment variable must be set for standalone dashboard"
end

use Rack::Session::Cookie,
  key: "rails_pulse_session",
  secret: secret_key,
  same_site: :lax,
  max_age: 86400  # 1 day

run DashboardApp.new
