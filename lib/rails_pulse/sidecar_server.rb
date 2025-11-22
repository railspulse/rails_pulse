require 'rack'
require 'json'

module RailsPulse
  class SidecarServer
    def initialize(app = nil)
      @app = app
      @sync_adapter = RailsPulse::Adapters::SyncAdapter.new
    end

    def call(env)
      req = Rack::Request.new(env)

      case req.path_info
      when '/track'
        handle_tracking(req)
      when '/health'
        handle_health(req)
      else
        # Mount Rails Pulse engine for dashboard
        if defined?(RailsPulse::Engine)
          RailsPulse::Engine.call(env)
        else
          [404, {}, ['Not Found']]
        end
      end
    end

    private

    def handle_tracking(req)
      begin
        # Parse incoming tracking data (both HTTP and UNIX socket send JSON)
        data = JSON.parse(req.body.read, symbolize_names: true)

        # Log that we received tracking data
        puts "[#{Time.now.strftime('%H:%M:%S')}] Received tracking: #{data[:method]} #{data[:path]} (#{data[:duration]}ms)"

        # Persist data synchronously
        @sync_adapter.track_request(data)

        [202, {'content-type' => 'application/json'}, ['{\"status\":\"accepted\"}']]
      rescue JSON::ParserError => e
        puts "[#{Time.now.strftime('%H:%M:%S')}] ERROR: Bad Request - #{e.message}"
        [400, {}, ["Bad Request: #{e.message}"]]
      rescue => e
        puts "[#{Time.now.strftime('%H:%M:%S')}] ERROR: #{e.message}"
        Rails.logger.error "[RailsPulse::SidecarServer] Error: #{e.message}" if defined?(Rails)
        [500, {}, ['Internal Server Error']]
      end
    end

    def handle_health(req)
      health_status = {
        status: 'ok',
        adapter: 'sidecar',
        timestamp: Time.now.iso8601
      }

      [200, {'content-type' => 'application/json'}, [health_status.to_json]]
    end
  end
end
