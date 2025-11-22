require 'socket'
require 'json'

module RailsPulse
  module Adapters
    class SidecarAdapter < BaseAdapter
      def initialize
        @socket_path = RailsPulse.configuration.sidecar_socket
        @use_tcp = RailsPulse.configuration.sidecar_host.present?
        @host = RailsPulse.configuration.sidecar_host || 'localhost'
        @port = RailsPulse.configuration.sidecar_port || 3001
      end

      def track_request(data)
        # Skip if tracking is disabled (recursion prevention)
        return if RequestStore.store[:skip_recording_rails_pulse_activity]

        RequestStore.store[:skip_recording_rails_pulse_activity] = true

        begin
          # Send to sidecar server via UNIX socket or TCP
          send_to_sidecar(data)
        rescue => e
          Rails.logger.error "[RailsPulse::SidecarAdapter] Failed to send to sidecar: #{e.message}"
          # Non-blocking - don't fail the request
        ensure
          RequestStore.store[:skip_recording_rails_pulse_activity] = false
        end
      end

      def healthy?
        if @use_tcp
          tcp_healthy?
        else
          unix_socket_healthy?
        end
      end

      private

      def send_to_sidecar(data)
        if @use_tcp
          send_via_tcp(data)
        else
          send_via_unix_socket(data)
        end
      end

      def send_via_unix_socket(data)
        socket = UNIXSocket.new(@socket_path)

        # Send JSON data with newline delimiter
        socket.puts(data.to_json)
        socket.flush

        # Don't wait for response - fire and forget
        socket.close
      end

      def send_via_tcp(data)
        socket = TCPSocket.new(@host, @port)

        # Send HTTP POST request
        json_data = data.to_json
        request = "POST /track HTTP/1.1\r\n"
        request << "Host: #{@host}:#{@port}\r\n"
        request << "Content-Type: application/json\r\n"
        request << "Content-Length: #{json_data.bytesize}\r\n"
        request << "Connection: close\r\n"
        request << "\r\n"
        request << json_data

        socket.write(request)
        socket.flush
        socket.close
      end

      def unix_socket_healthy?
        return false unless File.exist?(@socket_path)

        socket = UNIXSocket.new(@socket_path)
        socket.close
        true
      rescue
        false
      end

      def tcp_healthy?
        socket = TCPSocket.new(@host, @port)
        socket.close
        true
      rescue
        false
      end
    end
  end
end
