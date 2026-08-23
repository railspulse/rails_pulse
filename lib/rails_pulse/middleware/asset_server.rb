require "rack/static"

module RailsPulse
  module Middleware
    class AssetServer < Rack::Static
      MIME_TYPES = {
        ".css" => "text/css",
        ".js" => "application/javascript",
        ".map" => "application/json",
        ".png" => "image/png",
        ".svg" => "image/svg+xml"
      }.freeze

      # "/rails-pulse-assets/0.3.3/rails-pulse.css" → lookup at
      # public/rails-pulse-assets/rails-pulse.css. Unversioned paths still work.
      VERSIONED_ASSET_PATH = %r{\A(/rails-pulse-assets/)(?:\d+\.\d+[\w.\-]*/)}.freeze

      def initialize(app, root, options = {})
        # Rack::Static expects (app, options) where options[:root] is the root path
        options = options.merge(root: root) if root.is_a?(String) || root.is_a?(Pathname)
        super(app, options)
      end

      def call(env)
        # Only handle requests for Rails Pulse assets
        unless rails_pulse_asset_request?(env)
          return @app.call(env)
        end

        env = env.dup
        env["PATH_INFO"] = strip_asset_version(env["PATH_INFO"])

        # Log asset requests for debugging
        RailsPulse.logger.debug "Asset request: #{env['PATH_INFO']}"

        # Call parent Rack::Static with error handling
        begin
          status, headers, body = super(env)

          # Add immutable cache headers for successful responses
          if status == 200
            headers.merge!(cache_headers)
            RailsPulse.logger.debug "Asset served successfully: #{env['PATH_INFO']}"
          elsif status == 404
            log_missing_asset(env["PATH_INFO"])
          end

          [ status, headers, body ]
        rescue => e
          log_asset_error(env["PATH_INFO"], e)
          @app.call(env)
        end
      end

      private

      def rails_pulse_asset_request?(env)
        env["PATH_INFO"]&.start_with?("/rails-pulse-assets/")
      end

      def strip_asset_version(path)
        path.to_s.sub(VERSIONED_ASSET_PATH, '\1')
      end

      def cache_headers
        if defined?(Rails) && Rails.env.development?
          { "Cache-Control" => "no-cache, no-store, must-revalidate", "Pragma" => "no-cache" }
        else
          {
            "Cache-Control" => "public, max-age=31536000, immutable",
            "Vary" => "Accept-Encoding",
            "Expires" => (Time.now + 1.year).httpdate
          }
        end
      end

      def log_missing_asset(path)
        RailsPulse.logger.warn "Asset not found: #{path}"
      end

      def log_asset_error(path, error)
        RailsPulse.logger.error "Error serving asset #{path}: #{error.message}"
        RailsPulse.logger.error error.backtrace.join("\n") if RailsPulse.logger.debug?
      end
    end
  end
end
