#!/usr/bin/env ruby

require 'socket'
require 'json'

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
  require_relative 'rails_pulse'
end

# Load the sidecar server class
require_relative 'rails_pulse/sidecar_server'

module RailsPulse
  class UnixSocketServer
    def initialize(socket_path)
      @socket_path = socket_path
      @server = nil
    end

    def start
      # Remove old socket if it exists
      File.delete(@socket_path) if File.exist?(@socket_path)

      @server = UNIXServer.new(@socket_path)
      File.chmod(0666, @socket_path)

      # Disable output buffering so logs appear immediately
      $stdout.sync = true
      $stderr.sync = true

      puts "Rails Pulse sidecar listening on #{@socket_path}"

      # Load the Rack app
      rack_app = RailsPulse::SidecarServer.new

      loop do
        client = @server.accept

        Thread.new do
          handle_client(client, rack_app)
        end
      end
    rescue Interrupt
      puts "\nShutting down..."
      shutdown
    end

    def shutdown
      @server&.close
      File.delete(@socket_path) if File.exist?(@socket_path)
    end

    private

    def handle_client(client, rack_app)
      # Read JSON data (newline delimited)
      data = client.readline.chomp

      # Convert to Rack env
      env = {
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/track',
        'rack.input' => StringIO.new(data),
        'CONTENT_TYPE' => 'application/json',
        'CONTENT_LENGTH' => data.bytesize.to_s
      }

      # Process via Rack app
      status, headers, body = rack_app.call(env)

      # Don't send response for UNIX socket (fire-and-forget)
      client.close
    rescue => e
      puts "Error handling client: #{e.message}"
      client.close rescue nil
    end
  end
end

# Run if executed directly
if __FILE__ == $0
  socket_path = ENV['RAILS_PULSE_SOCKET'] || '/tmp/rails_pulse.sock'
  server = RailsPulse::UnixSocketServer.new(socket_path)
  server.start
end
