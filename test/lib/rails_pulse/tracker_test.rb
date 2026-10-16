require "test_helper"

class RailsPulse::TrackerTest < ActiveSupport::TestCase
  def setup
    super
    RailsPulse::SchemaCheck.reset!
    RailsPulse::Tracker.reset_rollups!
  end

  def teardown
    RailsPulse::SchemaCheck.reset!
    RailsPulse::Tracker.reset_rollups!
    super
  end

  # Schema Gate Tests

  test "track_request persists a request when the schema is current" do
    assert_difference "RailsPulse::Request.count", 1 do
      RailsPulse::Tracker.track_request(tracking_data)
    end
  end

  test "track_request persists nothing while the schema is outdated" do
    RailsPulse::SchemaCheck.stubs(:expected_schema).returns("rails_pulse_routes" => [ "ghost" ])

    assert_no_difference [ "RailsPulse::Request.count", "RailsPulse::Route.count" ] do
      RailsPulse::Tracker.track_request(tracking_data)
    end
  end

  # Rollup Fold Tests (detail: false payloads from detail capture)

  test "a folded request creates no request or operation rows" do
    assert_no_difference [ "RailsPulse::Request.count", "RailsPulse::Operation.count" ] do
      RailsPulse::Tracker.track_request(folded_tracking_data)
    end
  end

  test "a folded request still creates its route" do
    assert_difference "RailsPulse::Route.count", 1 do
      RailsPulse::Tracker.track_request(folded_tracking_data)
    end
  end

  test "a folded request lands in route and query rollups after a flush" do
    data = folded_tracking_data
    RailsPulse::Tracker.track_request(data)

    assert_difference "RailsPulse::Rollup.count", 2 do
      RailsPulse::Tracker.flush_rollups!
    end

    route = RailsPulse::Route.find_by!(path: "/tracker-test")
    route_rollup = RailsPulse::Rollup.find_by!(rollupable_type: "RailsPulse::Route", rollupable_id: route.id)

    assert_equal 1, route_rollup.count
    assert_equal 1, route_rollup.status_2xx
    assert_in_delta 12.5, route_rollup.sum_duration.to_f, 1e-6
    assert_equal data[:occurred_at].beginning_of_hour, route_rollup.period_start

    query_rollup = RailsPulse::Rollup.find_by!(rollupable_type: "RailsPulse::Query")

    assert_equal 1, query_rollup.count
    assert_in_delta 3.25, query_rollup.sum_duration.to_f, 1e-6
  end

  test "a folded request's SQL still creates its query record" do
    assert_difference "RailsPulse::Query.count", 1 do
      RailsPulse::Tracker.track_request(folded_tracking_data)
    end
  end

  test "a second flush replaces the writer's rollup row instead of adding one" do
    RailsPulse::Tracker.track_request(folded_tracking_data(operations: []))
    RailsPulse::Tracker.flush_rollups!

    RailsPulse::Tracker.track_request(folded_tracking_data(operations: []))

    assert_no_difference "RailsPulse::Rollup.count" do
      RailsPulse::Tracker.flush_rollups!
    end

    assert_equal 2, RailsPulse::Rollup.where(rollupable_type: "RailsPulse::Route").sum(:count)
  end

  test "flush with nothing folded writes nothing" do
    assert_no_difference "RailsPulse::Rollup.count" do
      RailsPulse::Tracker.flush_rollups!
    end
  end

  private

  def tracking_data
    {
      method: "GET",
      path: "/tracker-test",
      duration: 12.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid,
      controller_action: "home#index",
      occurred_at: Time.current,
      response_size_bytes: 128,
      operations: []
    }
  end

  def folded_tracking_data(operations: nil)
    operations ||= [
      {
        operation_type: "sql",
        actual_sql: "SELECT * FROM widgets WHERE id = 1",
        label: "SELECT * FROM widgets WHERE id = 1",
        duration: 3.25
      }
    ]
    {
      method: "GET",
      path: "/tracker-test",
      controller_action: "home#index",
      duration: 12.5,
      status: 200,
      occurred_at: Time.current,
      detail: false,
      operations: operations
    }
  end
end
