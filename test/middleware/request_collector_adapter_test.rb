require "test_helper"

module RailsPulse
  module Middleware
    class RequestCollectorAdapterTest < ActionDispatch::IntegrationTest
      setup do
        # Delete in correct order due to foreign keys
        RailsPulse::Operation.delete_all
        RailsPulse::Request.delete_all
        RailsPulse::Route.delete_all
        RailsPulse.configuration.async = false  # Use sync mode for tests
      end

      test "middleware tracks successful requests in sync mode" do
        assert_difference -> { RailsPulse::Request.count }, 1 do
          get "/"

          assert_response :success
        end

        request = RailsPulse::Request.last

        assert_equal 200, request.status
        assert_not request.is_error, "Expected is_error to be false for 200 response"
        assert_operator request.duration, :>, 0
        assert_operator request.operations.count, :>, 0
      end

      test "middleware tracks error requests in sync mode" do
        # Need a route that raises an error - using a non-existent route
        assert_difference -> { RailsPulse::Request.count }, 1 do
          get "/nonexistent"

          assert_response :not_found
        end

        request = RailsPulse::Request.last

        assert_equal 404, request.status
      end

      test "middleware passes complete tracking data to tracker" do
        captured_data = nil

        # Intercept the tracker's track_request to see what data it receives
        RailsPulse::Tracker.singleton_class.class_eval do
          alias_method :original_track_request, :track_request
          define_method(:track_request) do |data|
            captured_data = data
            original_track_request(data)
          end
        end

        begin
          get "/"

          # Verify the middleware passed all required fields
          assert_not_nil captured_data
          assert_equal "GET", captured_data[:method]
          assert_equal "/", captured_data[:path]
          assert_kind_of Numeric, captured_data[:duration]
          assert_equal 200, captured_data[:status]
          refute captured_data[:is_error]
          assert_predicate captured_data[:request_uuid], :present?
          assert_predicate captured_data[:occurred_at], :present?
          assert_kind_of Array, captured_data[:operations]
        ensure
          # Restore original method
          RailsPulse::Tracker.singleton_class.class_eval do
            alias_method :track_request, :original_track_request
            remove_method :original_track_request
          end
        end
      end
    end
  end
end
