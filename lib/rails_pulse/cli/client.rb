require "net/http"
require "openssl"
require "uri"
require "json"
require_relative "config"

module RailsPulse
  module CLI
    # HTTP client for the read-only JSON API under <mount>/api/v1.
    class Client
      class ApiError < StandardError; end

      def initialize(config = nil)
        @config = config || Config.load
      end

      def get(path, params = {})
        uri = URI("#{@config.url}#{@config.mount_path}/api/v1#{path}")
        uri.query = URI.encode_www_form(params) unless params.empty?

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          req = Net::HTTP::Get.new(uri)
          req["X-Rails-Pulse-Token"] = @config.token
          response = http.request(req)
          raise_for(response) unless response.is_a?(Net::HTTPSuccess)
          parse(response, uri)
        end
      rescue URI::InvalidURIError => e
        raise ApiError, "the configured URL and mount path do not form a valid URL (#{e.message})"
      rescue OpenSSL::SSL::SSLError => e
        raise ApiError, "TLS failed talking to #{uri.host}:#{uri.port} (#{e.message})"
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
        raise ApiError, "could not connect to #{uri.host}:#{uri.port} (#{e.message})"
      end

      private

      # A 200 that is not JSON is almost always the wrong URL or mount path
      # answered by the host app itself: a login page or a catch-all route.
      def parse(response, uri)
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        type = response["Content-Type"].to_s.split(";").first
        raise ApiError, "#{uri} answered with #{type.to_s.empty? ? 'a non-JSON body' : type} rather than JSON. " \
                        "Check the URL and mount path ('rails-pulse configure' or RAILS_PULSE_MOUNT_PATH)"
      end

      def raise_for(response)
        body = begin
          JSON.parse(response.body.to_s)
        rescue JSON::ParserError
          {}
        end
        body = {} unless body.is_a?(Hash)

        # The API explains a 400 or 401 in the body ("Invalid sort. Valid
        # values: ..."); relay it rather than only the status line.
        message = "#{response.code} #{response.message}".strip
        message = "#{message}: #{body["error"]}" if body["error"].is_a?(String) && !body["error"].empty?
        raise ApiError, message
      end
    end
  end
end
