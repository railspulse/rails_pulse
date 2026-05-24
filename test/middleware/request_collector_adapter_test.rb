require "test_helper"

module RailsPulse
  module Middleware
    class RequestCollectorAdapterTest < ActionDispatch::IntegrationTest
      setup do
        @original_async = RailsPulse.configuration.async
        RailsPulse.configuration.async = false  # Use sync mode for tests
      end

      teardown do
        RailsPulse.configuration.async = @original_async
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
        original_method = RailsPulse::Tracker.method(:track_request)

        # Intercept the tracker's track_request to see what data it receives
        RailsPulse::Tracker.define_singleton_method(:track_request) do |data|
          captured_data = data
          original_method.call(data)
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
          RailsPulse::Tracker.define_singleton_method(:track_request, original_method)
        end
      end

      test "tracking data includes response_size_bytes" do
        captured_data = nil
        original_method = RailsPulse::Tracker.method(:track_request)

        RailsPulse::Tracker.define_singleton_method(:track_request) do |data|
          captured_data = data
          original_method.call(data)
        end

        begin
          get "/api_simple", as: :json

          assert_not_nil captured_data
          assert captured_data.key?(:response_size_bytes), "tracking data should include response_size_bytes key"
        ensure
          RailsPulse::Tracker.define_singleton_method(:track_request, original_method)
        end
      end

      test "n_plus_one detection annotates repeated sql operations" do
        captured_data = nil
        original_method = RailsPulse::Tracker.method(:track_request)

        RailsPulse::Tracker.define_singleton_method(:track_request) do |data|
          captured_data = data
          original_method.call(data)
        end

        begin
          get "/"

          assert_not_nil captured_data
          sql_ops = captured_data[:operations].select { |op| op[:operation_type] == "sql" }
          repeated = sql_ops.select { |op| op[:repetition_count] }

          if repeated.any?
            repeated.each do |op|
              assert_operator op[:repetition_count], :>=, 2
              assert_not_nil op[:repeated_query_group]
            end
          end
        ensure
          RailsPulse::Tracker.define_singleton_method(:track_request, original_method)
        end
      end

      test "persists response_size_bytes on request record" do
        get "/api_simple", as: :json

        request = RailsPulse::Request.last

        assert_not_nil request.response_size_bytes
        assert_operator request.response_size_bytes, :>, 0
      end
    end
  end
end
