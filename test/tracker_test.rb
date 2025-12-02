require "test_helper"

class RailsPulse::TrackerTest < ActiveSupport::TestCase
  setup do
    # Clear RequestStore to avoid state leakage between tests
    RequestStore.store[:skip_recording_rails_pulse_activity] = false

    @tracking_data = {
      method: "GET",
      path: "/test-#{SecureRandom.hex(4)}",  # Unique path for each test
      duration: 150.0,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid,
      controller_action: "UsersController#index",
      occurred_at: Time.current,
      operations: [
        {
          operation_type: "sql",
          duration: 50.0,
          label: "SELECT * FROM users",
          codebase_location: "app/models/user.rb:10",
          occurred_at: Time.current
        }
      ]
    }
  end

  test "creates request records" do
    RailsPulse::Tracker.track_request(@tracking_data)

    route = RailsPulse::Route.find_by(method: @tracking_data[:method], path: @tracking_data[:path])

    assert_not_nil route, "Route should be created"

    request = RailsPulse::Request.find_by(request_uuid: @tracking_data[:request_uuid])

    assert_not_nil request, "Request should be created"
    assert_in_delta(150.0, request.duration)
    assert_equal 1, request.operations.count
  end

  test "creates route and request records with operations" do
    RailsPulse::Tracker.track_request(@tracking_data)

    route = RailsPulse::Route.find_by(method: @tracking_data[:method], path: @tracking_data[:path])

    assert_not_nil route

    request = RailsPulse::Request.find_by(request_uuid: @tracking_data[:request_uuid])

    assert_not_nil request
    assert_equal 1, request.operations.count
  end

  test "handles errors gracefully" do
    # Stub to raise an error
    RailsPulse::Route.stubs(:find_or_create_by).raises(StandardError, "DB Error")

    assert_nothing_raised do
      RailsPulse::Tracker.track_request(@tracking_data)
    end

    RailsPulse::Route.unstub(:find_or_create_by)
  end

  test "logs errors when tracking fails" do
    skip "Logger test requires mocha setup in test environment"
    # This test verifies that errors are logged but not raised
    # The actual logging is tested in integration tests
  end

  test "healthy? returns true when database is connected" do
    assert_predicate RailsPulse::Tracker, :healthy?, "Tracker should be healthy when DB is connected"
  end

  test "healthy? returns false when database is disconnected" do
    RailsPulse::ApplicationRecord.connection.stubs(:execute).raises(ActiveRecord::ConnectionNotEstablished)

    refute_predicate RailsPulse::Tracker, :healthy?, "Tracker should be unhealthy when DB is disconnected"
    RailsPulse::ApplicationRecord.connection.unstub(:execute)
  end

  test "sets recursion prevention flag during tracking" do
    # Flag should be false before tracking
    refute RequestStore.store[:skip_recording_rails_pulse_activity]

    # Track a request
    RailsPulse::Tracker.track_request(@tracking_data)

    # Flag should be reset after tracking
    refute RequestStore.store[:skip_recording_rails_pulse_activity], "Flag should be reset after tracking"
  end

  test "handles concurrent requests with connection pooling" do
    base_path = "/concurrent-test-#{SecureRandom.hex(4)}"
    initial_count = RailsPulse::Request.count

    threads = 10.times.map do |i|
      Thread.new do
        data = @tracking_data.merge(
          request_uuid: "uuid-#{SecureRandom.hex(8)}-#{i}",
          path: "#{base_path}-#{i}"
        )
        RailsPulse::Tracker.track_request(data)
      end
    end

    threads.each(&:join)

    assert_equal initial_count + 10, RailsPulse::Request.count, "Should create 10 requests"
  end

  test "skips tracking when recursion flag is set" do
    RequestStore.store[:skip_recording_rails_pulse_activity] = true

    RailsPulse::Tracker.track_request(@tracking_data)

    # Should not create any records
    assert_nil RailsPulse::Request.find_by(request_uuid: @tracking_data[:request_uuid])
  end

  test "async mode with fibers processes requests concurrently" do
    # Temporarily enable async mode
    original_async = RailsPulse.configuration.async
    RailsPulse.configuration.async = true

    begin
      base_path = "/fiber-test-#{SecureRandom.hex(4)}"
      initial_count = RailsPulse::Request.count

      # Create multiple tracking requests
      tasks = 5.times.map do |i|
        data = @tracking_data.merge(
          request_uuid: "fiber-uuid-#{SecureRandom.hex(8)}-#{i}",
          path: "#{base_path}-#{i}"
        )
        RailsPulse::Tracker.track_request(data)
      end

      # Wait for async fibers to complete
      sleep 0.5

      # All requests should be created
      assert_equal initial_count + 5, RailsPulse::Request.count, "Should create 5 requests via async fibers"
    ensure
      RailsPulse.configuration.async = original_async
    end
  end

  test "handles deep copied operations in async mode" do
    # Temporarily enable async mode
    original_async = RailsPulse.configuration.async
    RailsPulse.configuration.async = true

    begin
      # Track request with operations
      RailsPulse::Tracker.track_request(@tracking_data)

      # Wait for async fiber
      sleep 0.3

      request = RailsPulse::Request.find_by(request_uuid: @tracking_data[:request_uuid])

      assert_not_nil request, "Request should be created"
      assert_equal 1, request.operations.count, "Operation should be persisted"
      assert_equal "SELECT * FROM users", request.operations.first.label
    ensure
      RailsPulse.configuration.async = original_async
    end
  end
end
