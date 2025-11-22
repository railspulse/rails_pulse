# Load Rails environment - try multiple locations
if File.exist?('test/dummy/config/environment.rb')
  # Running from Rails Pulse gem root
  require_relative '../test/dummy/config/environment'
elsif File.exist?('config/environment.rb')
  # Running from a Rails app that has Rails Pulse installed
  require File.expand_path('config/environment', Dir.pwd)
else
  # Fallback - just load the basics we need
  puts "WARNING: Could not find Rails environment, loading minimal dependencies"
  require 'active_support/all'
  require 'active_record'
  $LOAD_PATH.unshift File.expand_path('../lib', __dir__)
  require 'rails_pulse'
end

# Disable output buffering so logs appear immediately
$stdout.sync = true
$stderr.sync = true

# Load the sidecar server class
require_relative 'rails_pulse/sidecar_server'

# Run the sidecar server
run RailsPulse::SidecarServer.new
