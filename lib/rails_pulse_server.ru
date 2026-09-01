# Load the host Rails environment. The dashboard is a mounted engine and needs
# the host's models, routes and initializer (authentication, database), so run
# this from the Rails application's root — or from the gem root, which loads
# the dummy app for development.
if File.exist?("test/dummy/config/environment.rb")
  require_relative "../test/dummy/config/environment"
elsif File.exist?("config/environment.rb")
  require File.expand_path("config/environment", Dir.pwd)
else
  abort <<~MESSAGE
    RailsPulse standalone dashboard: config/environment.rb not found in #{Dir.pwd}.

    Run from your Rails application's root directory:

      cd /path/to/your/app
      RAILS_ENV=production bundle exec rackup $(bundle show rails_pulse)/lib/rails_pulse_server.ru -p 3001

    RAILS_ENV selects the database and enables dashboard authentication.
  MESSAGE
end

# Disable output buffering so logs appear immediately
$stdout.sync = true
$stderr.sync = true

# Build the Rack app with session support
require "rack/session/cookie"
require "securerandom"
require_relative "rails_pulse/rack_compat"

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

# `secure` keeps the session cookie off plain HTTP in production. Set
# RAILS_PULSE_INSECURE_SESSION=1 only for a deliberately non-TLS deployment
# (a private network with no reverse proxy in front).
use Rack::Session::Cookie,
  key: "rails_pulse_session",
  secret: secret_key,
  same_site: :lax,
  httponly: true,
  secure: Rails.env.production? && ENV["RAILS_PULSE_INSECURE_SESSION"].blank?,
  max_age: 86400  # 1 day

run DashboardApp.new
