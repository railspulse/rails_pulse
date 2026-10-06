require "net/http"
require "zlib"
require "json"

module RailsPulse
  module Cloud
    # Posts one batch to Rails Pulse Cloud. Gzipped JSON, the contract
    # version in a header, and short timeouts: it runs in a background job,
    # but a hung connection would still hold a worker.
    class Client
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15
      PATH = "/v1/batches".freeze

      Response = Struct.new(:status, :body, :headers, keyword_init: true) do
        # The JSON error body Cloud sends, or an empty hash.
        def error
          parsed = JSON.parse(body.to_s)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end

        def message
          error["message"].presence || "HTTP #{status}"
        end

        def header(name)
          headers[name.downcase]
        end
      end

      # Raised when Cloud could not be reached or did not answer in time.
      class Unavailable < StandardError; end

      def initialize(settings = RailsPulse.configuration.cloud)
        @settings = settings
      end

      # @param body [String] the batch as JSON
      # @return [Response]
      def post(body)
        uri = URI.join(@settings.url.to_s.chomp("/") + "/", PATH.delete_prefix("/"))
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@settings.api_key}"
        request["Content-Type"] = "application/json"
        request["Content-Encoding"] = "gzip"
        request["Rails-Pulse-Contract"] = Batch::CONTRACT.to_s
        request["User-Agent"] = user_agent
        request.body = Zlib.gzip(body)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, write_timeout: READ_TIMEOUT) do |http|
          http.request(request)
        end
        Response.new(status: response.code.to_i, body: response.body, headers: response.each_header.to_h)
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, EOFError => e
        raise Unavailable, "#{e.class}: #{e.message}"
      end

      private

      def user_agent
        "rails_pulse/#{RailsPulse::VERSION} (ruby #{RUBY_VERSION}; rails #{Rails.version})"
      end
    end
  end
end
