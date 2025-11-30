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
  db_config = if ENV["RAILS_PULSE_DATABASE_URL"]
    { url: ENV["RAILS_PULSE_DATABASE_URL"] }
  elsif ENV["DATABASE_URL"]
    { url: ENV["DATABASE_URL"] }
  else
    {
      adapter: ENV.fetch("RAILS_PULSE_DB_ADAPTER", "postgresql"),
      host: ENV.fetch("RAILS_PULSE_DB_HOST", "localhost"),
      port: ENV.fetch("RAILS_PULSE_DB_PORT", "5432"),
      database: ENV.fetch("RAILS_PULSE_DB_NAME", "rails_pulse_production"),
      username: ENV.fetch("RAILS_PULSE_DB_USER", "postgres"),
      password: ENV.fetch("RAILS_PULSE_DB_PASSWORD", "")
    }
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
  RailsPulse::Base.establish_connection(db_config)

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
        { "Content-Type" => "application/json" },
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
use Rack::Session::Cookie,
  key: "rails_pulse_session",
  secret: ENV.fetch("SECRET_KEY_BASE", SecureRandom.hex(32)),
  same_site: :lax,
  max_age: 86400  # 1 day

run DashboardApp.new
