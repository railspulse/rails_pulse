require "test_helper"

module RailsPulse
  module Adapters
    class SyncAdapterTest < ActiveSupport::TestCase
      setup do
        @adapter = RailsPulse::Adapters::SyncAdapter.new
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

      test "tracks request and creates route record" do
        assert_difference -> { RailsPulse::Route.count }, 1 do
          @adapter.track_request(@tracking_data)
        end

        route = RailsPulse::Route.last
        assert_equal "GET", route.method
        assert_equal "/users", route.path
      end

      test "tracks request and creates request record" do
        assert_difference -> { RailsPulse::Request.count }, 1 do
          @adapter.track_request(@tracking_data)
        end

        request = RailsPulse::Request.last
        assert_equal 123.45, request.duration
        assert_equal 200, request.status
        assert_equal false, request.is_error
        assert_equal "UsersController#index", request.controller_action
      end

      test "tracks request with operations" do
        @tracking_data[:operations] = [
          {
            operation_type: "sql",
            duration: 10.5,
            label: "SELECT * FROM users",
            occurred_at: Time.current,
            codebase_location: "app/controllers/users_controller.rb:10"
          }
        ]

        assert_difference -> { RailsPulse::Operation.count }, 1 do
          @adapter.track_request(@tracking_data)
        end

        operation = RailsPulse::Operation.last
        assert_equal "sql", operation.operation_type
        assert_equal 10.5, operation.duration
      end

      test "reuses existing route" do
        # Create initial route
        @adapter.track_request(@tracking_data)

        # Track another request with same route but different UUID
        @tracking_data[:request_uuid] = SecureRandom.uuid
        assert_no_difference -> { RailsPulse::Route.count } do
          @adapter.track_request(@tracking_data)
        end
      end

      test "prevents recursion via RequestStore" do
        RequestStore.store[:skip_recording_rails_pulse_activity] = true

        assert_no_difference -> { RailsPulse::Request.count } do
          @adapter.track_request(@tracking_data)
        end
      ensure
        RequestStore.store[:skip_recording_rails_pulse_activity] = false
      end

      test "is healthy by default" do
        assert @adapter.healthy?
      end

      test "close does not raise error" do
        assert_nothing_raised do
          @adapter.close
        end
      end
    end
  end
end
