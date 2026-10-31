require "rack/static"
require "digest"
require "zlib"
require "stringio"

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

      # Text assets are gzipped once per file and held in memory: the gem ships
      # no .gz siblings, and compressing the JS bundle on every request would
      # cost more than the bytes it saves.
      COMPRESSIBLE_EXTENSIONS = %w[.css .js .map .svg].freeze

      # "/rails-pulse-assets/0.3.3/rails-pulse.css" → lookup at
      # public/rails-pulse-assets/rails-pulse.css. Unversioned paths still work.
      VERSIONED_ASSET_PATH = %r{\A(/rails-pulse-assets/)(\d+\.\d+[\w.\-]*)/}.freeze

      IMMUTABLE_CACHE_CONTROL = "public, max-age=31536000, immutable".freeze

      # Unversioned paths and versions other than the running gem's are still
      # served (a page rendered before a deploy may ask for the old version),
      # but must revalidate: the bytes behind them change with the gem.
      REVALIDATE_CACHE_CONTROL = "public, no-cache".freeze

      def initialize(app, root, options = {})
        # Rack::Static expects (app, options) where options[:root] is the root path
        options = options.merge(root: root) if root.is_a?(String) || root.is_a?(Pathname)
        @root = options[:root] || Dir.pwd
        @variants = {}
        @variants_lock = Mutex.new
        super(app, options)
      end

      def call(env)
        # Only handle requests for Rails Pulse assets
        unless rails_pulse_asset_request?(env)
          return @app.call(env)
        end

        env = env.dup
        current_version = requested_version(env["PATH_INFO"]) == RailsPulse::VERSION
        env["PATH_INFO"] = strip_asset_version(env["PATH_INFO"])

        # Log asset requests for debugging
        RailsPulse.logger.debug "Asset request: #{env['PATH_INFO']}"

        # Call parent Rack::Static with error handling
        begin
          status, headers, body = super(env)

          if status == 200
            status, headers, body = finish_response(env, headers, body, current_version)
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

      def requested_version(path)
        path.to_s[VERSIONED_ASSET_PATH, 2]
      end

      # Adds cache headers and the ETag, answers If-None-Match with 304, and
      # swaps in the gzipped body when the client accepts it.
      def finish_response(env, headers, body, current_version)
        headers = headers.merge(cache_headers(current_version))
        variant = variant_for(env["PATH_INFO"])
        return [ 200, headers, body ] unless variant

        headers["etag"] = variant[:etag]
        headers["vary"] = "Accept-Encoding" if variant[:gzip]

        if etag_matches?(env["HTTP_IF_NONE_MATCH"], variant[:etag])
          body.close if body.respond_to?(:close)
          headers.delete("content-length")
          headers.delete("content-type")
          return [ 304, headers, [] ]
        end

        if variant[:gzip] && accepts_gzip?(env["HTTP_ACCEPT_ENCODING"])
          body.close if body.respond_to?(:close)
          headers["content-encoding"] = "gzip"
          headers["content-length"] = variant[:gzip].bytesize.to_s
          body = env["REQUEST_METHOD"] == "HEAD" ? [] : [ variant[:gzip] ]
        end

        [ 200, headers, body ]
      end

      # Digest and gzipped bytes for a file, recomputed when its mtime or size
      # changes so rebuilt assets are picked up without a restart.
      def variant_for(path_info)
        file = asset_file(path_info)
        return unless file

        stat = ::File.stat(file)
        key = [ stat.mtime.to_f, stat.size ]

        @variants_lock.synchronize do
          cached = @variants[file]
          return cached if cached && cached[:key] == key

          content = ::File.binread(file)
          @variants[file] = {
            key: key,
            etag: %(W/"#{Digest::SHA256.hexdigest(content)[0, 32]}"),
            gzip: (gzip(content) if COMPRESSIBLE_EXTENSIONS.include?(::File.extname(file)))
          }
        end
      end

      def asset_file(path_info)
        relative = Rack::Utils.clean_path_info(Rack::Utils.unescape_path(path_info.to_s))
        file = ::File.join(@root.to_s, relative)
        file if ::File.file?(file)
      end

      def gzip(content)
        io = StringIO.new("".b)
        writer = Zlib::GzipWriter.new(io, Zlib::BEST_COMPRESSION)
        writer.write(content)
        writer.close
        io.string
      end

      def accepts_gzip?(accept_encoding)
        return false if accept_encoding.to_s.empty?

        accept_encoding.split(",").any? do |coding|
          name, *params = coding.split(";").map(&:strip)
          next false unless name.to_s.casecmp?("gzip") || name == "*"

          q = params.find { |param| param.start_with?("q=") }
          q.nil? || q.delete_prefix("q=").to_f > 0
        end
      end

      def etag_matches?(if_none_match, etag)
        return false if if_none_match.to_s.empty?
        return true if if_none_match.strip == "*"

        opaque = etag.delete_prefix("W/")
        if_none_match.split(",").any? { |tag| tag.strip.delete_prefix("W/") == opaque }
      end

      # Lowercase keys: Rack 3 requires them, and Rack::Lint rejects mixed case.
      def cache_headers(current_version = true)
        if defined?(Rails) && Rails.env.development?
          { "cache-control" => "no-cache, no-store, must-revalidate", "pragma" => "no-cache" }
        elsif current_version
          {
            "cache-control" => IMMUTABLE_CACHE_CONTROL,
            "expires" => (Time.now + 1.year).httpdate
          }
        else
          { "cache-control" => REVALIDATE_CACHE_CONTROL }
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
