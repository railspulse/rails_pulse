require "test_helper"

module RailsPulse
  module Adapters
    class SidecarAdapterTest < ActiveSupport::TestCase
      setup do
        RailsPulse.configuration.tracking_adapter = :sidecar
        RailsPulse.configuration.sidecar_socket = "/tmp/rails_pulse_test.sock"
        @adapter = RailsPulse::Adapters::SidecarAdapter.new
        @tracking_data = {
          method: "GET",
          path: "/users",
          duration: 123.45,
          status: 200,
          is_error: false,
          request_uuid: SecureRandom.uuid,
          controller_action: "UsersController#index",
          occurred_at: Time.current,
          operations: []
        }
      end

      teardown do
        RailsPulse.configuration.tracking_adapter = :sync
      end

      test "sends data via UNIX socket when configured" do
        socket = mock("socket")
        socket.expects(:puts).with(instance_of(String))
        socket.expects(:flush)
        socket.expects(:close)

        UNIXSocket.stubs(:new).returns(socket)
        @adapter.track_request(@tracking_data)
      end

      test "sends JSON formatted data" do
        sent_data = nil

        socket = mock("socket")
        socket.expects(:puts).with do |data|
          sent_data = data
          true
        end
        socket.expects(:flush)
        socket.expects(:close)

        UNIXSocket.stubs(:new).returns(socket)
        @adapter.track_request(@tracking_data)

        parsed_data = JSON.parse(sent_data, symbolize_names: true)

        assert_equal "GET", parsed_data[:method]
        assert_equal "/users", parsed_data[:path]
      end

      test "sends data via TCP when host is configured" do
        RailsPulse.configuration.sidecar_host = "localhost"
        RailsPulse.configuration.sidecar_port = 3001
        adapter = RailsPulse::Adapters::SidecarAdapter.new

        socket = mock("socket")
        socket.expects(:write).with(instance_of(String))
        socket.expects(:flush)
        socket.expects(:close)

        TCPSocket.stubs(:new).returns(socket)
        adapter.track_request(@tracking_data)
      ensure
        RailsPulse.configuration.sidecar_host = nil
      end

      test "handles connection errors gracefully" do
        UNIXSocket.stubs(:new).raises(Errno::ENOENT)

        assert_nothing_raised do
          @adapter.track_request(@tracking_data)
        end
      end

      test "prevents recursion via RequestStore" do
        RequestStore.store[:skip_recording_rails_pulse_activity] = true

        # Socket should not be called
        UNIXSocket.expects(:new).never

        @adapter.track_request(@tracking_data)
      ensure
        RequestStore.store[:skip_recording_rails_pulse_activity] = false
      end

      test "healthy? returns false when socket does not exist" do
        RailsPulse.configuration.sidecar_socket = "/tmp/nonexistent_socket.sock"
        adapter = RailsPulse::Adapters::SidecarAdapter.new

        refute_predicate adapter, :healthy?
      end

      test "healthy? returns false when connection fails" do
        File.stubs(:exist?).returns(true)
        UNIXSocket.stubs(:new).raises(Errno::ECONNREFUSED)

        refute_predicate @adapter, :healthy?
      end

      test "close does not raise error" do
        assert_nothing_raised do
          @adapter.close
        end
      end
    end
  end
end
