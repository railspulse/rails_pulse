require "test_helper"

class RailsPulse::TrackerTest < ActiveSupport::TestCase
  setup do
    @original_async = RailsPulse.configuration.async
    @tracking_data = {
      method: "GET",
      path: "/users",
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
          codebase_location: "app/models/user.rb:10"
        }
      ]
    }
  end

  teardown do
    RailsPulse.configuration.async = @original_async
  end

  test "async mode returns immediately without blocking" do
    RailsPulse.configuration.async = true

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    RailsPulse::Tracker.track_request(@tracking_data)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    # Should return in less than 10ms (non-blocking)
    assert_operator elapsed, :<, 0.01, "Async mode should not block, took #{elapsed}s"
  end

  test "async mode creates records in background" do
    RailsPulse.configuration.async = true

    RailsPulse::Tracker.track_request(@tracking_data)

    # Wait for background thread
    sleep 0.2

    route = RailsPulse::Route.find_by(method: "GET", path: "/users")

    assert_not_nil route, "Route should be created"

    request = RailsPulse::Request.find_by(request_uuid: @tracking_data[:request_uuid])

    assert_not_nil request, "Request should be created"
    assert_in_delta(150.0, request.duration)
    assert_equal 1, request.operations.count
  end

  test "sync mode blocks until complete" do
    RailsPulse.configuration.async = false

    RailsPulse::Tracker.track_request(@tracking_data)

    # Data should be immediately available (no sleep needed)
    request = RailsPulse::Request.find_by(request_uuid: @tracking_data[:request_uuid])

    assert_not_nil request, "Request should be immediately available in sync mode"
  end

  test "sync mode creates records immediately" do
    RailsPulse.configuration.async = false

    RailsPulse::Tracker.track_request(@tracking_data)

    route = RailsPulse::Route.find_by(method: "GET", path: "/users")

    assert_not_nil route

    request = RailsPulse::Request.find_by(request_uuid: @tracking_data[:request_uuid])

    assert_not_nil request
    assert_equal 1, request.operations.count
  end

  test "handles errors gracefully in async mode" do
    RailsPulse.configuration.async = true

    # Stub to raise an error
    RailsPulse::Route.stub :find_or_create_by, ->(*) { raise StandardError, "DB Error" } do
      assert_nothing_raised do
        RailsPulse::Tracker.track_request(@tracking_data)
        sleep 0.1
      end
    end
  end

  test "handles errors gracefully in sync mode" do
    RailsPulse.configuration.async = false

    # Stub to raise an error
    RailsPulse::Route.stub :find_or_create_by, ->(*) { raise StandardError, "DB Error" } do
      assert_nothing_raised do
        RailsPulse::Tracker.track_request(@tracking_data)
      end
    end
  end

  test "logs errors when tracking fails" do
    RailsPulse.configuration.async = false

    logged_messages = []
    mock_logger = Minitest::Mock.new
    mock_logger.expect(:error, nil) { |msg| logged_messages << msg; true }
    mock_logger.expect(:debug?, false)

    RailsPulse.configuration.logger = mock_logger

    RailsPulse::Route.stub :find_or_create_by, ->(*) { raise StandardError, "DB Error" } do
      RailsPulse::Tracker.track_request(@tracking_data)
    end

    assert logged_messages.any? { |msg| msg.include?("Failed to persist tracking data") }
  end

  test "healthy? returns true when database is connected" do
    assert_predicate RailsPulse::Tracker, :healthy?, "Tracker should be healthy when DB is connected"
  end

  test "healthy? returns false when database is disconnected" do
    RailsPulse::Base.connection.stub :active?, false do
      refute_predicate RailsPulse::Tracker, :healthy?, "Tracker should be unhealthy when DB is disconnected"
    end
  end

  test "sets recursion prevention flag in sync mode" do
    RailsPulse.configuration.async = false

    # Flag should be false before tracking
    refute RequestStore.store[:skip_recording_rails_pulse_activity]

    # Stub to check flag during tracking
    flag_during_tracking = nil
    RailsPulse::Route.stub :find_or_create_by, ->(*) {
      flag_during_tracking = RequestStore.store[:skip_recording_rails_pulse_activity]
      RailsPulse::Route.new
    } do
      RailsPulse::Tracker.track_request(@tracking_data)
    end

    # Flag should be true during tracking
    assert flag_during_tracking, "Flag should be set during tracking"

    # Flag should be reset after tracking
    refute RequestStore.store[:skip_recording_rails_pulse_activity], "Flag should be reset after tracking"
  end

  test "handles concurrent requests in async mode" do
    RailsPulse.configuration.async = true

    threads = 10.times.map do |i|
      Thread.new do
        data = @tracking_data.merge(request_uuid: "uuid-#{i}")
        RailsPulse::Tracker.track_request(data)
      end
    end

    threads.each(&:join)
    sleep 0.3  # Wait for all background threads

    assert_equal 10, RailsPulse::Request.count, "Should create 10 requests"
  end

  test "skips tracking when recursion flag is set" do
    RequestStore.store[:skip_recording_rails_pulse_activity] = true

    RailsPulse.configuration.async = false
    RailsPulse::Tracker.track_request(@tracking_data)

    # Should not create any records
    assert_nil RailsPulse::Request.find_by(request_uuid: @tracking_data[:request_uuid])
  end
end
