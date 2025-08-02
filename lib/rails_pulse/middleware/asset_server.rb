require "rack/static"

module RailsPulse
  module Middleware
    class AssetServer < Rack::Static
      MIME_TYPES = {
        ".css" => "text/css",
        ".js" => "application/javascript",
        ".map" => "application/json",
        ".svg" => "image/svg+xml"
      }.freeze

      def initialize(app, root, options = {})
        @logger = Rails.logger if defined?(Rails)
        # Rack::Static expects (app, options) where options[:root] is the root path
        options = options.merge(root: root) if root.is_a?(String) || root.is_a?(Pathname)
        super(app, options)
      end

      def call(env)
        # Only handle requests for Rails Pulse assets
        unless rails_pulse_asset_request?(env)
          return @app.call(env)
        end

        # Log asset requests for debugging
        @logger&.debug "[Rails Pulse] Asset request: #{env['PATH_INFO']}"

        # Set proper MIME type based on file extension
        set_content_type(env)

        # Call parent Rack::Static with error handling
        begin
          status, headers, body = super(env)

          # Add immutable cache headers for successful responses
          if status == 200
            headers.merge!(cache_headers)
            @logger&.debug "[Rails Pulse] Asset served successfully: #{env['PATH_INFO']}"
          elsif status == 404
            log_missing_asset(env["PATH_INFO"]) if @logger
          end

          [ status, headers, body ]
        rescue => e
          log_asset_error(env["PATH_INFO"], e) if @logger
          @app.call(env)
        end
      end

      private

      def rails_pulse_asset_request?(env)
        env["PATH_INFO"]&.start_with?("/rails-pulse-assets/")
      end

      def set_content_type(env)
        path = env["PATH_INFO"]
        extension = File.extname(path)

        if MIME_TYPES.key?(extension)
          env["rails_pulse.content_type"] = MIME_TYPES[extension]
        end
      end

      def cache_headers
        {
          "Cache-Control" => "public, max-age=31536000, immutable",
          "Vary" => "Accept-Encoding",
          "Expires" => (Time.now + 1.year).httpdate
        }
      end

      def log_missing_asset(path)
        @logger.warn "[Rails Pulse] Asset not found: #{path}"
      end

      def log_asset_error(path, error)
        @logger.error "[Rails Pulse] Error serving asset #{path}: #{error.message}"
        @logger.error error.backtrace.join("\n") if @logger.debug?
      end
    end
  end
end
