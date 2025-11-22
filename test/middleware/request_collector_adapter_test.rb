require "test_helper"

module RailsPulse
  module Middleware
    class RequestCollectorAdapterTest < ActionDispatch::IntegrationTest
      setup do
        # Delete in correct order due to foreign keys
        RailsPulse::Operation.delete_all
        RailsPulse::Request.delete_all
        RailsPulse::Route.delete_all
        RailsPulse.configuration.tracking_adapter = :sync
        RailsPulse.reset_adapter!
      end

      test "middleware tracks successful requests with sync adapter" do
        assert_difference -> { RailsPulse::Request.count }, 1 do
          get "/"
          assert_response :success
        end

        request = RailsPulse::Request.last
        assert_equal 200, request.status
        assert_not request.is_error, "Expected is_error to be false for 200 response"
        assert request.duration > 0
        assert request.operations.count > 0
      end

      test "middleware tracks error requests with sync adapter" do
        # Need a route that raises an error - using a non-existent route
        assert_difference -> { RailsPulse::Request.count }, 1 do
          get "/nonexistent"
          assert_response :not_found
        end

        request = RailsPulse::Request.last
        assert_equal 404, request.status
      end

      test "middleware passes complete tracking data to adapter" do
        captured_data = nil

        # Intercept the adapter's track_request to see what data it receives
        original_adapter = RailsPulse.adapter
        RailsPulse.adapter.define_singleton_method(:track_request) do |data|
          captured_data = data
          original_adapter.method(:track_request).super_method.call(data)
        end

        get "/"

        # Verify the middleware passed all required fields
        assert_not_nil captured_data
        assert_equal "GET", captured_data[:method]
        assert_equal "/", captured_data[:path]
        assert captured_data[:duration].is_a?(Numeric)
        assert_equal 200, captured_data[:status]
        assert_equal false, captured_data[:is_error]
        assert captured_data[:request_uuid].present?
        assert captured_data[:occurred_at].present?
        assert captured_data[:operations].is_a?(Array)
      end

      test "sidecar adapter sends data without creating database records" do
        RailsPulse.configuration.tracking_adapter = :sidecar
        RailsPulse.configuration.sidecar_socket = '/tmp/test.sock'
        RailsPulse.reset_adapter!

        # Mock the socket so it doesn't actually try to connect
        socket = mock('socket')
        socket.stubs(:puts)
        socket.stubs(:flush)
        socket.stubs(:close)
        UNIXSocket.stubs(:new).returns(socket)

        # With sidecar adapter, no DB records should be created directly
        assert_no_difference -> { RailsPulse::Request.count } do
          get "/"
          assert_response :success
        end
      end
    end
  end
end
